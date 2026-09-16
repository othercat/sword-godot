# SPDX-License-Identifier: MIT
extends SceneTree
## The production clear_effective_cross_fade owner: the real opening chain
## parks on the bounded renderer transition, refuses stale ids, advances
## phase by phase and only the endpoint releases the waiter. This headless
## replay acts as the display owner (one advance per frame); real per-phase
## window presentation is the scene display's act and is verified in the
## window lanes, not here.
const ProbeConfig = preload("res://tests/fixtures/pal98_new_game_probe.gd")
const NewGame = preload("res://src/native_pal98_new_game.gd")
const Package = preload("res://src/native_package.gd")

class ReplayClock:
	var frame := 0
	func consume(units: int) -> Dictionary:
		frame += units
		return {"consumed": units, "total": frame}

class ReplayRuntime:
	func answer(request: Dictionary) -> Dictionary:
		if request.kind == "fade_event_pump": return {"completed": true, "pumped": request.events}
		return {"completed": true}

class NamedGap:
	var seen: Array = []
	func answer(request: Dictionary) -> Dictionary:
		seen.append(request.kind)
		var result := {"completed": true}
		if request.get("state") is Dictionary: result.state = request.state.duplicate(true)
		return result

var checks: Array = []
var failed: int = 0
func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func finish(args: Array) -> void:
	var f = FileAccess.open(args[1], FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks": checks, "passed": checks.size() - failed, "failed": failed}, "  ")); f.close()
	quit(1 if failed else 0)

func _assembly(package):
	var game = NewGame.new()
	check(game.open(package), "package binds: " + game.error)
	# The probe scope keeps its named doubles EXCEPT the transition under test.
	game.bind_recording_dialogue_for_probe()
	var gaps = NamedGap.new()
	for kind in ["restore_dialog_background_without_initial_page", "upper_dialog_layout",
			"start_frame_and_process_events", "update_viewport_and_party_position",
			"render_scene_frame", "sync_party_for_redraw", "render_scene",
			"advance_party_movement", "sync_party_frames", "main_frame",
			"move_and_animate_event_object_one_step", "play_midi", "play_sound_effect"]:
		game.bind_named_double(kind, gaps)
	game.bind_clock(ReplayClock.new())
	game.bind_runtime(ReplayRuntime.new())
	game.bind_key_map([0,1,2,3,4,5,6,7,8],0,8)
	return game

## Drives the real opening chain; plays the display owner for the parked
## transition. Returns {result, parked} where parked counts the phases seen.
func _drive_chain(game, cancel_at_park: bool) -> Dictionary:
	var result: Dictionary = game.begin()
	var parked := 0
	for ordinal in range(16384):
		if result.has("error") or result.get("completed"): return {"result": result, "parked": parked}
		if result.get("awaiting_transition", false):
			parked += 1
			if parked == 1:
				check(game.advance_transition("stale-id").has("error"), "a stale phase id is refused")
				check(game.transition_phase_frame("stale-id").has("error"), "a stale frame id is refused")
				check(game.finish_transition("stale-id").has("error"), "a stale completion id is refused")
				check(not game.tick(PackedInt32Array(), true).get("completed", true),
					"ticks during the park neither drive the chain nor lose it")
				if cancel_at_park:
					game.cancel()
					return {"result": {"cancelled": true}, "parked": parked}
			var advanced: Dictionary = game.advance_transition(String(result.get("id", "")))
			if advanced.has("error"): return {"result": {"error": "transition: " + str(advanced.error)}, "parked": parked}
			if advanced.get("exhausted", false):
				result = game.finish_transition(String(result.get("id", "")))
			continue
		result = game.tick(PackedInt32Array([0,0,0,0,0,0,0,0,
			2 if result.get("pending_effect", {}).get("kind") == "poll_input" else 0]), true)
	return {"result": {"error": "replay budget exceeded"}, "parked": parked}

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]): quit(2); return
	var package = Package.new()
	if not package.load_package(args[0]): push_error("package rejected: " + str(package.error)); quit(2); return

	var cancelled = _assembly(package)
	var fresh: Dictionary = cancelled.new_state(0x12345, ProbeConfig.configuration())
	check(not fresh.has("error"), "the probe initial state prepares: " + str(fresh.get("error", "")))
	if fresh.has("error"): finish(args); return
	var cancelled_run: Dictionary = _drive_chain(cancelled, true)
	check(cancelled_run.result.get("cancelled", false), "the real chain parks on the production transition")
	check(cancelled_run.parked >= 1, "the park happened after real phases")
	check(not cancelled.has_pending_transition(), "cancel clears the parked transition")
	var receipts_after_cancel: Array = cancelled.renderer.receipts()
	var completed_after_cancel: int = receipts_after_cancel.filter(
		func(r): return r.get("kind") == "clear_effective_cross_fade" and r.get("completed", false)).size()
	check(completed_after_cancel == 0, "a cancelled transition publishes no completion receipt")

	var game = _assembly(package)
	var second: Dictionary = game.new_state(0x12345, ProbeConfig.configuration())
	check(not second.has("error"), "the second assembly prepares a fresh chain")
	if second.has("error"): finish(args); return
	var run: Dictionary = _drive_chain(game, false)
	var result: Dictionary = run.result
	check(not result.has("error"), "the chain completes through the real transition: " + str(result.get("error", "")))
	check(run.parked >= 1, "the production transition parked at least once")
	if result.has("error"): finish(args); return
	check(result.get("enters", []) == [1, 2], "the intro still chains scene 1 into scene 2: " + str(result.get("enters", [])))
	check("load_map_gop:12" in result.get("trace", []), "the post-transition chain still loads scene 2's own map")
	var receipts: Array = game.renderer.receipts()
	var completions: Array = receipts.filter(
		func(r): return r.get("kind") == "clear_effective_cross_fade" and r.get("completed", false))
	check(completions.size() == 1, "exactly one completion receipt exists")
	if completions.size() == 1:
		check(true, "the opening call requested phases=" + str(completions[0].phases)
			+ " delay=" + str(completions[0].delay) + " lane_gaps=" + str(completions[0].lane_gaps))
		check(completions[0].phases >= 1 and completions[0].endpoint_sha256 == completions[0].target_sha256,
			"the production receipt pins the actual phases and the exact endpoint")
	var failed_checks: int = checks.filter(func(x): return not x.passed).size()
	var f = FileAccess.open(args[1], FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks": checks, "passed": checks.size() - failed_checks, "failed": failed_checks}, "  ")); f.close()
	quit(1 if failed_checks else 0)
