# SPDX-License-Identifier: MIT
extends RefCounted
## Original-source capability inspection for the formal app. Every capability
## row comes from probing the real owners (package admission, the formal
## session's own guard, the new-game chain, the missing audio backend) and
## carries the owner's own refusal text; nothing here hardcodes
## "everything is supported" or fakes a playable original package.
const Package = preload("res://src/native_package.gd")
const NewGame = preload("res://src/native_pal98_new_game.gd")
const Session = preload("res://src/native_session.gd")

## A minimal recording receiver bound by exact name so the opening-chain
## detection can run past audio requests. It is a detection stub, not a
## backend, and never claims audio capability.
class Stub:
	func answer(_request: Dictionary) -> Dictionary:
		return {"completed": true}

## Explicit detection inputs for the unverified opening words. They are the
## same pinned probe shapes the window suites use and are NOT recovered
## original initialization values.
static func _detection_inputs() -> Dictionary:
	var inventory := PackedByteArray(); inventory.resize(1536)
	var trail: Array = []
	for index in range(5): trail.append({"x": 0, "y": 0, "direction_word": 0})
	return {"globals": {"current_scene": 0, "requested_scene": 1, "resource_flags": 12,
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

static func inspect(path: String) -> Dictionary:
	var candidate = Package.new()
	if not candidate.load_package(path):
		return {"error": "package admission refused: " + str(candidate.error)}
	return report_for(candidate)

## Build the capability report for one already-loaded candidate. The formal
## session probe uses its own Session instance and never touches a live one.
static func report_for(candidate) -> Dictionary:
	if candidate == null or not candidate.error.is_empty():
		return {"error": "admission requires a loaded package candidate"}
	var has_original: bool = candidate.pal98_sources != null and candidate.pal98_graphics != null
	var readable: Dictionary = {}
	var provenance: Variant = candidate.manifest.get("provenance")
	readable.source_id = provenance.get("source_id", "") if provenance is Dictionary else ""
	readable.original_components = has_original
	if not has_original:
		# A world-preview author package without pal98 original components:
		# the formal session branch still probes; original rows report absent.
		var capabilities: Array = []
		capabilities.append({"name": "package_admission", "present": true,
			"detail": str(candidate.manifest.get("package_id", ""))})
		var session = Session.new()
		var activated: bool = session.activate(candidate)
		capabilities.append({"name": "ordinary_session_play", "present": activated,
			"detail": "activated" if activated else session.error})
		capabilities.append({"name": "original_opening_chain", "present": false,
			"detail": "the package carries no pal98 original source/graphics components"})
		capabilities.append({"name": "audio_backend", "present": false,
			"detail": "the formal runtime has no audio backend owner"})
		var playable: bool = true
		for cap in capabilities: playable = playable and cap.present
		return {"readable": readable, "capabilities": capabilities, "playable": playable}
	var records = candidate.pal98_graphics.open_records()
	if records == null: return {"error": "graphics records unavailable"}
	readable.graphics_fingerprint = str(records.metadata().get("source_fingerprint", ""))
	var map20: Dictionary = records.decoded_chunk("MAP.MKF", 20)
	var map12: Dictionary = records.decoded_chunk("MAP.MKF", 12)
	readable.map20_readable = not map20.has("error")
	readable.map12_readable = not map12.has("error")
	var day: Dictionary = records.palette(0, 0)
	var night: Dictionary = records.palette(0, 1)
	readable.day_palette_rgb6 = int(day.value.size()) if not day.has("error") else 0
	readable.night_palette_readable = not night.has("error")
	readable.data3_bytes = candidate.pal98_sources.copy_chunk("data", 3).size()
	var scene_records = candidate.pal98_sources.open_records()
	var scene1: Dictionary = scene_records.scene_for_runtime_id(1) if scene_records != null else {"error": "source records unavailable"}
	readable.scene1_readable = not scene1.has("error")
	var capabilities: Array = []
	capabilities.append({"name": "package_admission", "present": true,
		"detail": str(candidate.manifest.get("package_id", ""))})
	var session = Session.new()
	var activated: bool = session.activate(candidate)
	capabilities.append({"name": "ordinary_session_play", "present": activated,
		"detail": "activated" if activated else session.error})
	var game = NewGame.new()
	var chain := {"present": false, "detail": ""}
	var audio := {"needed_stub": false}
	if not game.open(candidate):
		chain.detail = game.error
	else:
		var state: Dictionary = game.new_state_from_source(0x12345, "explicit_replay", _detection_inputs())
		if state.has("error"):
			chain.detail = str(state.error)
		else:
			var bare: Dictionary = game.begin()
			if bare.has("error") and str(bare.error).contains("play_midi"):
				audio.needed_stub = true
				game.bind_named_double("play_midi", Stub.new())
				game.bind_named_double("play_sound_effect", Stub.new())
				bare = game.begin()
			if bare.has("error"):
				chain.detail = str(bare.error)
			else:
				chain.present = true
				chain.detail = "enters=" + str(game.enters_seen) + " parked_kind=" + game.pending_kind()
	capabilities.append({"name": "original_opening_chain", "present": chain.present,
		"detail": chain.detail,
		"note": "audio requests are served by in-module named stubs for detection only"})
	var audio_detail: String = "the formal runtime has no audio backend owner"
	if audio.needed_stub:
		audio_detail += "; the detection chain's audio requests were served by a named stub"
	else:
		audio_detail += "; the opening detection ended before any audio request"
	capabilities.append({"name": "audio_backend", "present": false, "detail": audio_detail})
	var playable: bool = true
	for cap in capabilities: playable = playable and cap.present
	return {"readable": readable, "capabilities": capabilities, "playable": playable}

## One human-readable summary line per capability for app display.
static func summary(report: Dictionary) -> String:
	if report.has("error"): return report.error
	var lines: Array = []
	var readable: Dictionary = report.readable
	lines.append("来源身份 %s；图形指纹 %s" % [readable.source_id, readable.graphics_fingerprint])
	lines.append("MAP20 可读=%s，MAP12 可读=%s，日/夜调色板=%s/%s，DATA3=%d 字节，场景1 可读=%s" % [
		str(readable.map20_readable), str(readable.map12_readable),
		str(readable.day_palette_rgb6 > 0), str(readable.night_palette_readable),
		readable.data3_bytes, str(readable.scene1_readable)])
	for cap in report.capabilities:
		lines.append(("[可] " if cap.present else "[缺] ") + cap.name + "：" + cap.detail)
	lines.append("当前可正式试玩：%s" % str(report.playable))
	return "\n".join(lines)
