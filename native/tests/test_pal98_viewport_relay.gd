# SPDX-License-Identifier: MIT
extends "res://tests/test_pal98_enter_script.gd"
## Astra DAY-01 regressions through the real EnterScript/Commands relay.
## Host replies are explicit doubles; this is not rendering/gameplay acceptance.

func _run_viewport(words: Array, background_globals: Dictionary = {}) -> Dictionary:
	var source = _source([0, 0], [1, 0], [words, [1, 0, 0, 0]])
	var owner = _owner(source)
	var result: Dictionary = owner.start(_fixture(source), 1, 1)
	var requests: Array = []
	for index in range(32):
		if not result.has("request"): return {"result": result, "requests": requests}
		var request: Dictionary = result.request
		requests.append(request.duplicate(true))
		var answer: Dictionary = request.state.duplicate(true)
		if request.kind == "render_current_map_background": answer.globals.merge(background_globals, true)
		result = owner.resume(request.id, {"completed": true, "state": answer})
	owner.cancel()
	return {"result": {"error": "viewport relay test budget"}, "requests": requests}

func _failure_recovery() -> void:
	var source = _source([0, 0], [1, 0], [[0x007F, 30, 60, 0xFFFE], [1, 0, 0, 0]])
	var responses: Array = [
		{"label": "host error", "response": {"error": "injected background failure"}},
		{"label": "missing completion", "response": {}},
		{"label": "false completion", "response": {"completed": false}},
		{"label": "non-dictionary state", "response": {"completed": true, "state": 0}},
		{"label": "missing backing", "response": {"completed": true, "state": {}}},
		{"label": "continuation arithmetic", "response": {"completed": true}, "bad_anchor": true}
	]
	for trial in responses:
		var owner = _owner(source)
		var state: Dictionary = _fixture(source)
		var original: Dictionary = state.duplicate(true)
		var first: Dictionary = owner.start(state, 1, 1)
		if not first.has("request"):
			check(false, trial.label + ": initial request unavailable"); continue
		var response: Dictionary = trial.response.duplicate(true)
		if trial.get("bad_anchor", false):
			response.state = first.request.state.duplicate(true)
			response.state.globals.world_x = -32768
		var failed_step: Dictionary = owner.resume(first.request.id, response)
		check(failed_step.has("error") and not failed_step.has("state") and state == original
			and not failed_step.get("diagnostic", {}).is_empty() and not failed_step.get("trace", []).is_empty(),
			trial.label + ": failure keeps diagnostics/trace and publishes no candidate")
		var restarted: Dictionary = owner.start(state, 1, 1)
		check(restarted.has("request"), trial.label + ": the same owner restarts without an extra cancel")
		if not restarted.has("request"): owner.cancel(); continue
		var stale: Dictionary = owner.resume(first.request.id, {"completed": true, "state": first.request.state})
		check(stale.has("error") and str(stale.error).contains("stale")
			and first.request.id != restarted.request.id,
			trial.label + ": the previous generation's receipt is refused")
		var finished: Dictionary = _drive(owner, restarted).result
		check(not finished.has("error") and finished.has("return_entry"),
			trial.label + ": rejecting the old receipt does not interrupt the restarted invocation")

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 1 or FileAccess.file_exists(args[0]) or DirAccess.dir_exists_absolute(args[0]): quit(2); return
	var zero_count = _run_viewport([0x007F, 5, 7, 0])
	check(not zero_count.result.has("error") and zero_count.result.state.globals.viewport_x == 869
		and zero_count.result.state.globals.viewport_y == 919,
		"[5,7,0] follows the nonzero three-argument OR delta branch through EnterScript")
	var absolute = _run_viewport([0x007F, 30, 60, 0xFFFE])
	check(not absolute.result.has("error") and absolute.requests.map(func(r): return r.kind)
		== ["render_current_map_background", "start_frame_and_process_events", "render_scene_frame"],
		"negative A2 has background/frame/render in order and no viewport update")
	var restored = _run_viewport([0x007F, 0, 0, 0xFFFF])
	check(not restored.result.has("error") and restored.requests.is_empty(),
		"the special restore returns without any host helper")
	var written_back = _run_viewport([0x007F, 30, 60, 0xFFFE], {"viewport_x": 900})
	check(not written_back.result.has("error") and written_back.result.state.globals.party_x == 124
		and written_back.result.state.party_records[0].screen_x == 124
		and written_back.result.state.party_records[2].screen_x == 156,
		"the background's viewport 900 drives the later anchor and member shifts")
	check(written_back.requests.size() == 3 and written_back.requests[0].state.globals.party_x == 160
		and written_back.requests[1].state.globals.party_x == 124,
		"the background sees the old anchor; the following frame sees its dependent recomputation")
	var reanchor = _run_viewport([0x007F, 0, 0, 0], {"viewport_x": 900, "party_x": 200})
	check(not reanchor.result.has("error") and reanchor.result.state.globals.party_x == 200
		and reanchor.result.state.party_records[2].screen_x == 232
		and not reanchor.requests.map(func(r): return r.kind).has("update_viewport_and_party_position"),
		"re-anchor keeps the host-written anchor and then writes A2=-1 without recomputing it")
	_failure_recovery()
	var file = FileAccess.open(args[0], FileAccess.WRITE)
	if file == null: quit(2); return
	file.store_string(JSON.stringify({"passed": checks.size() - failed, "failed": failed, "checks": checks}, "\t"))
	file.close()
	print("viewport relay: ", checks.size(), " checks, ", failed, " failed")
	quit(0 if failed == 0 else 1)
