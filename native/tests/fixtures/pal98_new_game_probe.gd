# SPDX-License-Identifier: MIT
extends RefCounted
## Explicit synthetic probe configuration, not recovered original initialization.
static func configuration() -> Dictionary:
	var inventory := PackedByteArray(); inventory.resize(1536)
	var opening := {"current_scene": 0, "requested_scene": 1, "resource_flags": 29,
		"party_x": 160, "party_y": 112, "viewport_x": 0, "viewport_y": 0,
		"world_x": 0, "world_y": 0, "previous_x": 0, "previous_y": 0,
		"previous_viewport_x": 0, "previous_viewport_y": 0,
		"loaded_map_id": 0, "member_last": 0, "follower_count": 0, "battle_mode": 0,
		"midi_track": 0, "battle_music_track": 0, "day_night_word": 0, "fade_gate_word": 0,
		"direction_word": 0, "party_layer_word": 0, "fbp_mode_word": 0,
		"ffxy_max_x": 1696, "ffxy_max_y": 1840,
		"view_offset_x": 0, "view_offset_y": 0, "transition_cadence": 0, "transition_progress": 0,
		"walk_phase_word": 0, "leader_frame_offset_word": 0, "party_frame_offset_word": 0,
		"wave_phase": 0, "wave_amplitude": 0, "trigger_success_word": 0}
	return {"globals": opening,
		
		"dialogue": {"local_x": 101, "local_y": 102, "title_x": 12, "title_y": 8, "origin_x": 44,
			"origin_y": 26, "mode": 1, "line_count": 0, "boxed_count": 0, "draw_x": 201, "draw_y": 202,
			"icon": 2, "skip_word": 0, "delay_units": 1, "input_action": 99, "capture_gate": 1,
			"restore_gate": 0, "colours": [79, 45, 26, 141], "timer_counter": 0},
		"roles": [0],
		"inventory_bytes": inventory,
		"party_records": [{"role_id": 0, "x": 160, "y": 112, "current_frame": 0}],
		"party_trail": [{"x": 0, "y": 0, "direction_word": 0}, {"x": 0, "y": 0, "direction_word": 0},
			{"x": 0, "y": 0, "direction_word": 0}, {"x": 0, "y": 0, "direction_word": 0},
			{"x": 0, "y": 0, "direction_word": 0}]}

## Explicit synthetic nominal ticks and no-input replies for component probes.
## This replay explicitly supplies fresh presses at poll requests (including
## character skip). It is not evidence of physical input or elapsed time.
static func run(game, limit: int = 8192) -> Dictionary:
	var result: Dictionary = game.begin()
	for ordinal in range(limit):
		if result.has("error") or result.get("completed"): return result
		result = game.tick(PackedInt32Array([0,0,0,0,0,0,0,0,2 if result.get("pending_effect", {}).get("kind") == "poll_input" else 0]), true)
	return {"error": "probe nominal tick budget exceeded", "last": result,
		"entry_pc": game._pending_dialogue.get("pc"), "entry": game._pending_dialogue.get("entry"),
		"texts": game.dialogue_host.texts().size(), "dialogue": game.state.get("dialogue", {})}

class NamedGap:
	var seen: Array = []
	func answer(request: Dictionary) -> Dictionary:
		seen.append(request.kind)
		var result := {"completed": true}
		if request.get("state") is Dictionary: result.state = request.state.duplicate(true)
		return result

## Explicitly scoped replay gaps, not production implementations.
static func bind_gaps(game, audio: bool = true):
	game.bind_recording_dialogue_for_probe()
	var owner = NamedGap.new()
	for kind in ["clear_effective_cross_fade", "restore_dialog_background_without_initial_page",
			"upper_dialog_layout", "start_frame_and_process_events", "update_viewport_and_party_position",
			"render_scene_frame", "sync_party_for_redraw", "render_scene", "advance_party_movement",
			"sync_party_frames", "main_frame", "move_and_animate_event_object_one_step"]:
		game.bind_named_double(kind, owner)
	if audio:
		game.bind_named_double("play_midi", owner); game.bind_named_double("play_sound_effect", owner)
	return owner
