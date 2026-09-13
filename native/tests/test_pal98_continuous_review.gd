# SPDX-License-Identifier: MIT
extends SceneTree
## Independent rejection, address and ordering vectors for the 84cfe3c review.
const Probe = preload("res://src/native_pal98_collision_probe.gd")
const InputDirection = preload("res://src/native_pal98_direction_input.gd")
const Facing = preload("res://src/native_pal98_walk_facing.gd")
const Commands = preload("res://src/native_pal98_script_commands.gd")
const Package = preload("res://src/native_package.gd")
var checks: Array = []
var failed := 0
func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)
func zeros(n: int) -> PackedByteArray:
	var b := PackedByteArray(); b.resize(n); return b
func events(count: int = 0) -> Dictionary:
	var slots: Array = []; slots.resize(160)
	for i in range(count): slots[i] = zeros(32)
	return {"event_count": count, "active_slots": slots}
func probe_map(at: int, x: int, y: int) -> Dictionary:
	var map = zeros(65536); map.encode_u16(at, 0x2000)
	var probe = Probe.new(); probe.bind(map, events())
	return probe.probe(x, y)
class EffectsDouble:
	var kinds: Array = []
	func answer(r: Dictionary) -> Dictionary:
		kinds.append(r.kind)
		if r.kind == "sync_party_formation_and_frames":
			return {"completed": true, "party_records": r.state.party_records.duplicate(true)}
		return {"completed": true, "state": r.state.duplicate(true)}
func state() -> Dictionary:
	return {"globals": {"viewport_x": 880, "viewport_y": 920, "party_x": 160, "party_y": 112,
		"previous_x": 1024, "previous_y": 1024, "world_x": 1024, "world_y": 1024,
		"direction_word": 3, "walk_phase_word": 0, "leader_frame_offset_word": 0, "party_frame_offset_word": 0,
		"member_last": 1, "follower_count": 0},
		"party_trail": [{"x": 1010, "y": 1000, "direction_word": 2},
			{"x": 1000, "y": 992, "direction_word": 3}, {"x": 990, "y": 984, "direction_word": 3},
			{"x": 980, "y": 976, "direction_word": 3}, {"x": 970, "y": 968, "direction_word": 3}],
		"party_records": [{"role_id": 0, "x": 160, "y": 112, "current_frame": 3},
			{"role_id": 1, "x": 172, "y": 98, "current_frame": 3}]}
func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]): quit(2); return
	check(probe_map(0, 0, 0).get("accepted") == false, "exgm1 selected lower descriptor blocks")
	check(probe_map(2, 0, 0).get("accepted") == true, "exgm1 does not read the upper descriptor")
	check(probe_map(4, 0, 0).get("accepted") == true, "half zero ignores adjacent half one")
	check(probe_map(0, 16, 8).get("accepted") == true, "half one ignores adjacent half zero")
	check(probe_map(4, 16, 8).get("accepted") == false, "half one reads its own lower word")
	check(probe_map(8, 32, 0).get("accepted") == false, "next column uses eight byte stride")
	check(probe_map(512, 0, 16).get("accepted") == false, "next row uses 512 byte stride")
	var stale = events(1); stale.active_slots[1] = zeros(32); stale.active_slots[1].encode_s16(12, 2)
	var p = Probe.new(); p.bind(zeros(65536), stale)
	check(p.probe(0, 0).get("accepted") == true, "inactive retained event backing does not collide")
	stale.event_count = 0; stale.active_slots[0].encode_s16(12, 2); p.bind(zeros(65536), stale)
	check(p.probe(0, 0).get("accepted") == true, "zero current event count skips all retained slots")
	var bad = events(1); bad.active_slots[0] = null
	check(not p.bind(zeros(65536), bad), "unknown current event prefix is rejected at bind")
	check(p.probe(0, 0).get("accepted") == true, "failed bind retains previous valid snapshot")
	var edge = events(1); edge.active_slots[0].encode_s16(12, 2)
	edge.active_slots[0].encode_s16(2, 32767); edge.active_slots[0].encode_s16(4, 1)
	p.bind(zeros(65536), edge)
	check(p.probe(0, 0).get("accepted") == false, "exgm2 signed WORD distance sum wraps before comparison")
	var input = InputDirection.new()
	check(input.resolve([true,0,0,0,0,0,0,0], [0,1,2,3,4,5,6,7]).has("error"), "boolean key level is not silent release")
	check(input.resolve([4,0,0,0,0,0,0,0], [0,1,2,3,4,5,6,7]).has("error"), "invalid key state is rejected")
	check(input.convert_to_isometric(5, 0).has("error"), "isometric conversion rejects non-unit direction")
	check(input.probe_and_prepare({"x": 65536,"y": 0}, {"x": 0,"y": 0}, 1, 1, p).has("error"), "out-of-WORD party anchor is rejected")
	var facing = Facing.new()
	for kind in ["start_frame_and_process_events", "update_viewport_and_party_position", "render_scene_frame"]:
		check(facing.answer({"kind": kind,"state": state()}).has("error"), "unbound " + kind + " cannot acknowledge work")
	check(facing.answer({"kind": "sync_members_from_trail","state": state()}).has("error"),
		"unbound formation/frame work cannot acknowledge member sync")
	var source = state(); var before = source.duplicate(true)
	var first_run: Dictionary = facing.answer({"kind":"post_move_update","state":source})
	check(first_run.has("error") and source == before, "post-move refuses unbound member work without publishing partial trail or globals")
	check(facing.answer({"kind":"face_party_toward","state":source.globals,"delta_x":16,"delta_y":8}).has("error"), "flat globals are not a source state")
	var effects = EffectsDouble.new(); facing.bind_fallback(effects); facing.bind_member_sync(effects)
	facing.executed.clear()
	var moved = facing.answer({"kind":"post_move_update","state":source})
	check(not moved.has("error") and moved.state.globals.previous_x == 1024, "post-move does not overwrite caller-owned previous world")
	check(facing.executed == ["rotate_party_trail", "sync_members_from_trail"], "movement executes rotate then sync in original order: " + str(facing.executed))
	var head: Dictionary = moved.state.party_trail[0]
	check(head.get("x") == 1024 and head.get("y") == 1024 and head.get("direction_word") == 3
		and moved.state.party_trail[1].get("x") == 1010,
		"the sync owner writes the real shifted trail head, not a fabrication")
	var package = Package.new()
	if not package.load_package(args[0]): push_error(package.error); quit(2); return
	var commands = Commands.new(); commands.load_source(package.pal98_sources)
	var command_state = {"globals":{"battle_mode":0,"move_dx":1,"move_dy":-1,"resource_flags":7}}
	var result = commands.consume(command_state, {"words":[0x0078,5,0,0],"entry":1,"event_id":0})
	check(not result.has("error") and result.state.globals.battle_mode == 5, "0078 writes A0 before calling T212")
	check(result.get("requests", []).size() == 1 and result.requests[0].kind == "load_resources_if_needed", "0078 requests immediate resource reload before next command")
	check(result.state.globals.move_dx == 1 and result.state.globals.move_dy == -1, "0078 leaves T212 entry clears to that owner")
	check(commands.case_facts(0x0078).range[1] == "0x0042571E", "0078 case end is exclusive at 42571E")
	var output = {"suite":"test_pal98_continuous_review","checks":checks,"passed":checks.size()-failed,"failed":failed}
	var f = FileAccess.open(args[1],FileAccess.WRITE); f.store_string(JSON.stringify(output,"  ")+"\n"); f.close()
	quit(1 if failed else 0)
