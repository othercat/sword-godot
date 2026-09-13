# SPDX-License-Identifier: MIT
extends SceneTree
## The production input frame tick: a right-key press moves the viewport along
## the isometric diagonal, faces and phases the party through the real owners,
## and the T209 draw requests computed from the new state carry the new
## positions and frames. A blocked candidate keeps the party in place with the
## stationary frame work and the draw requests still published; an event-prox
## refusal and the unbound member executor are refused by name.
const Facing = preload("res://src/native_pal98_walk_facing.gd")
const MemberSync = preload("res://src/native_pal98_member_sync.gd")
const CollisionProbe = preload("res://src/native_pal98_collision_probe.gd")
const InputFrame = preload("res://src/native_pal98_input_frame.gd")
const Occlusion = preload("res://src/native_pal98_map_occlusion.gd")

var checks: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _state() -> Dictionary:
	return {"globals": {"viewport_x": 864, "viewport_y": 912, "party_x": 160, "party_y": 112,
			"world_x": 1024, "world_y": 1024, "previous_x": 1024, "previous_y": 1024,
			"direction_word": 0, "walk_phase_word": 0,
			"leader_frame_offset_word": 0, "party_frame_offset_word": 0,
			"member_last": 1, "follower_count": 1},
		"party_trail": [
			{"x": 1024, "y": 1024, "direction_word": 0},
			{"x": 1008, "y": 1016, "direction_word": 0},
			{"x": 992, "y": 1008, "direction_word": 0},
			{"x": 976, "y": 1000, "direction_word": 0},
			{"x": 960, "y": 992, "direction_word": 0}],
		"party_records": [
			{"role_id": 0, "x": 160, "y": 112, "current_frame": 0},
			{"role_id": 1, "x": 160, "y": 112, "current_frame": 0},
			{"role_id": 3, "x": 160, "y": 112, "current_frame": 0}]}

func _events_state(count: int, event_x: int = 0, event_y: int = 0) -> Dictionary:
	var slots: Array = []
	for index in range(160):
		var row := PackedByteArray(); row.resize(32)
		if index == 0 and count > 0:
			row.encode_s16(2, event_x); row.encode_s16(4, event_y); row.encode_s16(12, 3)
		slots.append(row)
	return {"active_slots": slots, "event_count": count}

## A clean 65536-byte map with one optional blocked half-cell at the candidate.
func _map(block_world: Dictionary) -> PackedByteArray:
	var map := PackedByteArray(); map.resize(65536)
	if not block_world.is_empty():
		var cell: Dictionary = Occlusion.world_to_cell(block_world.x, block_world.y)
		var at: int = (cell.value.y * 512 + cell.value.x * 8 + cell.value.half * 4) & 65535
		map.encode_u16(at, map.decode_u16(at) | 0x2000)
	return map

func _assembly(block_world: Dictionary, events: Dictionary):
	var facing = Facing.new()
	var member = MemberSync.new()
	var probe = CollisionProbe.new()
	probe.bind(_map(block_world), events)
	member.bind_probe(probe)
	member.bind_frame_counts(func(_slot: int) -> int: return 3)
	check(member._probe != null, "the member executor binds its collision probe")
	facing.bind_member_sync(member)
	var frame = InputFrame.new()
	check(frame.bind(facing, probe, [0, 1, 2, 3, 4, 5, 6, 7], 0),
		"the production tick binds the movement, probe and key-map owners")
	return frame

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 1 or FileAccess.file_exists(args[0]) or DirAccess.dir_exists_absolute(args[0]): quit(2); return
	var right_press: PackedInt32Array = PackedInt32Array([0, 0, 0, 2, 0, 0, 0, 0])

	# An unbound tick refuses; a facing owner without the member executor is
	# refused by name through the whole chain.
	var bare = InputFrame.new()
	check(bare.tick(_state(), right_press).has("error"), "an unbound tick refuses by name")
	var lonely = InputFrame.new()
	var facing_only = Facing.new()
	check(lonely.bind(facing_only, CollisionProbe.new(), [0, 1, 2, 3, 4, 5, 6, 7], 0),
		"binding without the member executor still assembles")
	check(lonely.tick(_state(), right_press).has("error"),
		"the missing formation/frame executor refuses the tick instead of an ACK sync")

	# The real move: one right press steps the viewport along the iso diagonal
	# and the draw requests carry the new positions and walk-phase frames.
	var frame = _assembly({}, _events_state(0))
	var state: Dictionary = _state()
	var ticked: Dictionary = frame.tick(state, right_press)
	check(not ticked.has("error"), "the input tick completes: " + str(ticked.get("error", "")))
	if ticked.has("error"): finish(args); return
	check(ticked.input_move == true, "the right press produces a real move")
	check(ticked.state.globals.viewport_x == 880 and ticked.state.globals.viewport_y == 920,
		"the viewport stepped by the 16/8 isometric delta")
	check(ticked.state.globals.world_x == 1040 and ticked.state.globals.world_y == 1032,
		"the world words follow viewport+party after the step")
	check(ticked.state.globals.direction_word == 3, "extf faced the party along the move")
	check(ticked.state.globals.walk_phase_word == 1 and ticked.state.globals.leader_frame_offset_word == 1
		and ticked.state.globals.party_frame_offset_word == 2,
		"the walk phase advanced once with the recovered offset pair")
	check(ticked.state.party_trail[0].x == 1024 and ticked.state.party_trail[0].direction_word == 3,
		"the trail rotated: the newest entry holds the pre-move world and direction")
	check(ticked.state.party_records[1].x == 128 and ticked.state.party_records[1].y == 96,
		"the member adopted the probed trail position: %d,%d" % [ticked.state.party_records[1].x, ticked.state.party_records[1].y])
	check(ticked.state.party_records[2].x == 112 and ticked.state.party_records[2].y == 88,
		"the follower adopted trail[3] relative to the new viewport")
	var requests: Array = ticked.requests
	check(requests.size() == 3, "the tick published the three T209 party requests")
	if requests.size() == 3:
		check(requests[0].get("screen_x") == 160 and requests[0].get("screen_y") == 112
			and requests[0].get("frame_offset") == 10 and requests[0].get("follower") == false,
			"the leader request carries the new screen position and phase frame")
		check(requests[1].get("screen_x") == 128 and requests[1].get("screen_y") == 96
			and requests[1].get("frame_offset") == 2,
			"the member request carries the probed position and its offset frame")
		check(requests[2].get("screen_x") == 112 and requests[2].get("screen_y") == 88
			and requests[2].get("follower") == true,
			"the follower request is flagged and positioned from the trail")
	check(state.globals.viewport_x == 864, "the caller's own state was not mutated by the tick")

	# A blocked candidate keeps the party in place; the stationary branch still
	# settles the phase and the draw requests are still published.
	var blocked = _assembly({"x": 1040, "y": 1032}, _events_state(0))
	var parked: Dictionary = blocked.tick(_state(), right_press)
	check(not parked.has("error"), "a blocked candidate is a normal stationary tick: " + str(parked.get("error", "")))
	check(parked.get("input_move") == false, "the blocked candidate produced no move")
	check(parked.state.globals.viewport_x == 864 and parked.state.globals.world_x == 1024,
		"the blocked tick left the viewport and world in place")
	check(parked.state.globals.walk_phase_word == 2 and parked.state.globals.leader_frame_offset_word == 0,
		"the stationary branch settled the phase and cleared the offsets")
	check(parked.requests.size() == 3 and parked.requests[0].get("frame_offset") == 0
		and parked.requests[0].get("screen_x") == 160,
		"the stationary frame still publishes the draw requests")

	# An active event sitting on the candidate refuses through the event level.
	var crowded = _assembly({}, _events_state(1, 1040, 1032))
	var refused: Dictionary = crowded.tick(_state(), right_press)
	check(not refused.has("error") and refused.get("input_move") == false,
		"an active event on the candidate refuses the step")

	# Invalid key levels are refused with the caller state preserved.
	var bad_keys = _assembly({}, _events_state(0))
	var bad_state: Dictionary = _state()
	var invalid: Dictionary = bad_keys.tick(bad_state, PackedInt32Array([0, 0, 0, 7, 0, 0, 0, 0]))
	check(invalid.has("error"), "an out-of-range key level is refused by name")
	check(bad_state.globals.viewport_x == 864, "a refused tick preserved the caller state")

	finish(args)

func finish(args: Array) -> void:
	var output: Dictionary = {"suite": "test_pal98_input_frame", "checks": checks,
		"passed": checks.size() - failed, "failed": failed}
	var file = FileAccess.open(args[0], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n"); file.close()
	print("PASS %d/%d" % [checks.size() - failed, checks.size()])
	quit(1 if failed > 0 else 0)
