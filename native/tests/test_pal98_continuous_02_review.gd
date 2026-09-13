# SPDX-License-Identifier: MIT
extends SceneTree
## Independent ae51d12 counterexamples, including the real T209 and dialogue
## caller consumers. Formation/frame completion is explicitly doubled here;
## no ordinary Session, physical input, composed glyph or GPU claim is made.
const Facing = preload("res://src/native_pal98_walk_facing.gd")
const Requests = preload("res://src/native_pal98_scene_sprite_requests.gd")
const Renderer = preload("res://src/native_pal98_scene_render.gd")
const Dialogue = preload("res://src/native_pal98_dialogue_host.gd")
const Caller = preload("res://src/native_pal98_dialogue_caller.gd")
const CallerFixture = preload("res://tests/test_pal98_dialogue_caller.gd")
const Package = preload("res://src/native_package.gd")
var checks: Array = []
var failed := 0

class TransitionClock:
	var units := 0
	func consume(units_in: int) -> Dictionary:
		units += units_in
		return {"consumed": units_in, "total": units}

class FrameDouble:
	var fail := false
	var corrupt_identity := false
	func answer(request: Dictionary) -> Dictionary:
		if fail: return {"error": "injected frame selection failure"}
		var rows: Array = request.state.party_records.duplicate(true)
		rows[0].current_frame = 11
		if corrupt_identity: rows[0].role_id = 4
		return {"completed": true, "party_records": rows}

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func state() -> Dictionary:
	var trail: Array = []
	for i in range(5): trail.append({"x": 1024 - i * 16, "y": 1024 - i * 8, "direction_word": 3})
	return {"globals": {"viewport_x": 864, "viewport_y": 912, "party_x": 160, "party_y": 112,
		"previous_x": 1024, "previous_y": 1024, "direction_word": 3, "member_last": 0, "follower_count": 0},
		"party_trail": trail, "party_records": [{"role_id": 0, "x": 90, "y": 91,
			"current_frame": 7, "cache_word_offset": 37}]}

func rejection(facing, bad: Dictionary, kind: String, field: String) -> void:
	var before = bad.duplicate(true)
	var result = facing.answer({"kind": kind, "state": bad})
	check(result.has("error") and str(result.error).contains(field)
		and not result.has("state") and bad == before, "atomic rejection: " + kind + " / " + field)

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]): quit(2); return
	var facing = Facing.new(); var frames = FrameDouble.new()
	facing.bind_member_sync(frames)
	var source = state(); var before = source.duplicate(true)
	var synced = facing.answer({"kind": "sync_members_from_trail", "state": source})
	var drawn = Requests.party_requests(0, 0, synced.get("state", {}).get("party_records", []), 0)
	check(not drawn.has("error") and drawn.value[0].screen_x == 160 and drawn.value[0].screen_y == 112
		and drawn.value[0].frame_offset == 11, "new position and selected frame reach the real T209 consumer")
	check(source == before and synced.state.party_records[0].cache_word_offset == 37,
		"input and loaded sprite identity are preserved")
	for field in ["previous_x", "previous_y", "direction_word"]:
		var bad = state(); bad.globals.erase(field)
		rejection(facing, bad, "rotate_party_trail", field)
	for value in [65536, -32769, true, 1.5]:
		var bad = state(); bad.globals.previous_x = value
		rejection(facing, bad, "rotate_party_trail", "previous_x")
	for field in ["party_x", "party_y", "viewport_x", "viewport_y"]:
		var bad = state(); bad.globals.erase(field)
		rejection(facing, bad, "sync_members_from_trail", field)
	var bad = state(); bad.party_records[0] = 42
	rejection(facing, bad, "sync_members_from_trail", "record")
	for field in ["x", "y", "current_frame", "role_id"]:
		bad = state(); bad.party_records[0][field] = 65536
		rejection(facing, bad, "sync_members_from_trail", field)
	bad = state(); bad.party_trail[2].erase("x")
	rejection(facing, bad, "sync_members_from_trail", "x")
	bad = state(); bad.globals.member_last = 1
	rejection(facing, bad, "sync_members_from_trail", "records missing")
	bad = state(); bad.globals.member_last = 1
	bad.party_records.append({"role_id": 1, "x": 0, "y": 0, "current_frame": 0})
	rejection(Facing.new(), bad, "sync_members_from_trail", "formation probes/frame selection")
	rejection(Facing.new(), state(), "sync_members_from_trail", "frame selection")
	frames.fail = true
	rejection(facing, state(), "sync_members_from_trail", "injected")
	frames.fail = false; frames.corrupt_identity = true
	rejection(facing, state(), "sync_members_from_trail", "unrelated party fields")
	frames.corrupt_identity = false
	check(facing.answer({"kind": "sync_members_from_trail", "state": state()}).get("completed") == true,
		"same owner recovers after dependency rejection")
	bad = state(); bad.party_records.append(null)
	check(facing.answer({"kind": "sync_members_from_trail", "state": bad}).get("state", {}).get("party_records", []).size() == 2,
		"inactive backing is preserved without treating it as a current member")

	var package = Package.new()
	if not package.load_package(args[0]): push_error(package.error); quit(2); return
	var records = package.pal98_graphics.open_records()
	var renderer = Renderer.new(); renderer.bind(records)
	var a = {"globals": {"loaded_map_id": 20, "viewport_x": 448, "viewport_y": 368,
		"view_offset_x": 13, "view_offset_y": 9, "previous_viewport_x": 0, "previous_viewport_y": 0, "battle_mode": 0}}
	var first = renderer.render(a); var pixels_a = renderer.current_rgba(); renderer.capture_page()
	check(not first.has("error"), "real source MAP20 renders")
	var b = a.duplicate(true); b.globals.loaded_map_id = 12
	var second = renderer.render(b); var pixels_b = renderer.current_rgba()
	check(not second.has("error") and pixels_a != pixels_b, "distinct real MAP12 renders")
	check(renderer.restore_dialog_background().get("completed") == true and renderer.current_rgba() == pixels_a,
		"same-binding restore uses captured MAP20 rather than the latest MAP12")
	renderer.bind(records); renderer.render(b)
	check(renderer.restore_dialog_background().has("error") and renderer.current_rgba() == pixels_b,
		"rebinding invalidates old captured page")
	renderer.bind(records)
	var rejected = renderer.restore_dialog_background()
	var installed = renderer.install_palette(records.palette(0, 0).value)
	check(rejected.has("error") and installed.get("has_frame") == false and renderer.current_rgba().is_empty(),
		"failed restore cannot revive stale indices through later palette installation")

	# Inject a malformed internal palette to exercise failure after a valid capture.
	renderer.render(a); renderer.capture_page(); renderer.render(b)
	renderer._live_palette = PackedByteArray()
	var receipt_count = renderer.receipts().size()
	check(renderer.restore_dialog_background().has("error") and renderer.current_rgba() == pixels_b
		and renderer.receipts().size() == receipt_count, "restore validates before publishing any pixels or receipt")
	renderer.install_palette(records.palette(0, 0).value)
	check(renderer.current_rgba() == pixels_b, "failed restore leaves MAP12 indices as well as its RGBA intact")
	check(not renderer.bind(null) and renderer.restore_dialog_background().get("completed") == true
		and renderer.current_rgba() == pixels_a, "failed rebind preserves the old valid binding and capture")

	var fade = renderer.prepare_clear_cross_fade(b, 1, 2)
	check(fade.get("prepared") == true and fade.get("completed") != true, "pending dissolve cannot complete a command")
	check(fade.target_rgba == pixels_b and renderer.current_rgba() == pixels_a
		and fade.base_page.indices != fade.target_page.indices, "cross-fade keeps displayed A distinct from target B")
	check(fade.candidate_state.globals.view_offset_x == 0 and fade.candidate_state.globals.view_offset_y == 0
		and fade.candidate_state.globals.previous_viewport_x == 448
		and fade.candidate_state.globals.previous_viewport_y == 368
		and b.globals.view_offset_x == 13, "preparation retains T244 writeback only in its candidate state")
	check(renderer.bind_transition_clock(TransitionClock.new()), "the transition logical clock binds for real execution")
	var host = renderer.answer({"kind": "clear_effective_cross_fade", "state": b, "first": 1, "second": 2})
	check(host.get("completed") == true and host.state.globals.view_offset_x == 0
		and renderer.current_rgba() != pixels_a,
		"production host executes the recovered phases and completes at the endpoint with the T244 state")
	check(host.receipt.phases == 2 and str(host.receipt.named_gap).contains("adpic"),
		"the executed transition keeps its inclusive phase bound and the named adpic approximation")
	var battle = b.duplicate(true); battle.globals.battle_mode = 1
	check(renderer.prepare_clear_cross_fade(battle, 1, 2).has("error"), "unowned battle branch cannot reuse normal background preparation")
	check(renderer.restore_dialog_background().get("completed") == true and renderer.current_rgba() == pixels_a,
		"cross-fade preparation never overwrites the independent dialogue capture")
	var rendered_host = renderer.answer({"kind": "render_current_map_background", "state": b})
	check(rendered_host.get("completed") == true and rendered_host.state.globals.view_offset_x == 0,
		"completed background host carries the actual T244 state writeback")

	# Use the actual DialogueCaller request/event shapes, not invented display names.
	var helper = CallerFixture.new()
	var text_records = helper._records(["AB".to_ascii_buffer()])
	var dialogue = Dialogue.new(); dialogue.bind(package.pal98_sources); dialogue.bind_page_owner(renderer)
	var request = Caller.begin_message(text_records, 0, helper._context({"capture_gate": 0}))
	check(request.request.kind == "capture_background", "real dialogue caller emits the page capture request")
	var event = dialogue.answer(request.request)
	var after_capture = Caller.step(text_records, request.state, event)
	check(event == {"kind": "captured"} and not after_capture.has("error"), "page completion obeys the caller's exact event shape")
	renderer.render(a)
	event = dialogue.answer({"kind": "restore_background"})
	check(event == {"kind": "restored"} and renderer.current_rgba() == pixels_b,
		"dialogue restore reaches the same page captured by its real caller")
	renderer.bind(records)
	check(dialogue.answer({"kind": "restore_background"}).has("error"), "dialogue cannot acknowledge a stale page after source rebind")
	helper.free()
	var output = {"suite": "test_pal98_continuous_02_review", "checks": checks, "passed": checks.size() - failed,
		"failed": failed, "scope": "software page and state integration; explicit frame double"}
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n"); file.close()
	quit(1 if failed else 0)
