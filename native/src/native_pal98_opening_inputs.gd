# SPDX-License-Identifier: MIT
extends RefCounted
## The explicit unverified opening words that production callers must supply
## until the original cold-start initializer is recovered. T156 proves only
## the reload-tail InUse clear, never zero ItemId/Amount; globals, dialogue,
## trail and inventory therefore stay explicit caller inputs and are never
## renamed as recovered values.
##
## Recovered pins carried here: the T212 common-path party anchor (160,112).
## The remaining fields replay the verified suites' named neutral probe
## values, and the inventory is the named zero probe, not a recovered empty
## bag. The derived-vs-explicit split stays visible in every receipt.

static func inputs() -> Dictionary:
	var inventory := PackedByteArray(); inventory.resize(1536)
	var trail: Array = []
	for index in range(5): trail.append({"x": 0, "y": 0, "direction_word": 0})
	return {"globals": {"current_scene": 0, "requested_scene": 1, "resource_flags": 29,
				"party_x": 160, "party_y": 112, "viewport_x": 0, "viewport_y": 0,
				"world_x": 0, "world_y": 0, "previous_x": 0, "previous_y": 0,
				"previous_viewport_x": 0, "previous_viewport_y": 0,
				"loaded_map_id": 0, "member_last": 0, "follower_count": 0, "battle_mode": 0,
				"midi_track": 0, "battle_music_track": 0, "day_night_word": 0, "fade_gate_word": 0,
				"direction_word": 0, "party_layer_word": 0, "fbp_mode_word": 0,
				"ffxy_max_x": 1696, "ffxy_max_y": 1840,
				"view_offset_x": 0, "view_offset_y": 0, "transition_cadence": 0, "transition_progress": 0,
				"walk_phase_word": 0, "leader_frame_offset_word": 0, "party_frame_offset_word": 0,
				"wave_phase": 0, "wave_amplitude": 0, "trigger_success_word": 0},
		"dialogue": {"local_x": 101, "local_y": 102, "title_x": 12, "title_y": 8, "origin_x": 44,
			"origin_y": 26, "mode": 1, "line_count": 0, "boxed_count": 0, "draw_x": 201, "draw_y": 202,
			"icon": 2, "skip_word": 0, "delay_units": 1, "input_action": 99, "capture_gate": 1,
			"restore_gate": 0, "colours": [79, 45, 26, 141], "timer_counter": 0},
		"party_trail": trail, "inventory_bytes": inventory}

## What this provider can and cannot claim, for receipts and UI labels.
static func provenance() -> Dictionary:
	return {"party_anchor": "recovered T212 common path",
		"inventory": "named zero probe; T156 clears InUse only",
		"globals_dialogue_trail": "unverified neutral replay inputs"}
