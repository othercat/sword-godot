# SPDX-License-Identifier: MIT
extends SceneTree
## Component assembly over admitted MAP20: input direction, iso conversion,
## collision, facing and the position part of PostMoveUpdate. This harness
## supplies explicit dependency doubles; it is not an ordinary frame loop.
const DirectionInput = preload("res://src/native_pal98_direction_input.gd")
const CollisionProbe = preload("res://src/native_pal98_collision_probe.gd")
const Facing = preload("res://src/native_pal98_walk_facing.gd")
const Events = preload("res://src/native_pal98_scene_events.gd")
const Package = preload("res://src/native_package.gd")

## Component-only harness: frame, trail, clamping and physical input owners
## are not supplied. This is not a production frame-loop implementation.
class EffectsDouble:
	func answer(request: Dictionary) -> Dictionary:
		if request.kind == "sync_party_formation_and_frames":
			return {"completed": true, "party_records": request.state.party_records.duplicate(true)}
		return {"completed":true,"state":request.state.duplicate(true)}

var checks: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]) or DirAccess.dir_exists_absolute(args[1]): quit(2); return
	var package = Package.new()
	if not package.load_package(args[0]): push_error("package rejected: " + str(package.error)); quit(2); return
	var records = package.pal98_graphics.open_records()
	var storage = Events.new(); storage.load_source(package.pal98_sources)
	var map_bytes: PackedByteArray = records.decoded_chunk("MAP.MKF", 20).value
	var events_state: Dictionary = storage.source_state()

	var input = DirectionInput.new()
	var probe = CollisionProbe.new()
	check(probe.bind(map_bytes, events_state), "the probe binds the real MAP20 data")
	var facing = Facing.new(); facing.bind_fallback(EffectsDouble.new()); facing.bind_member_sync(EffectsDouble.new())

	var globals := {"viewport_x": 864, "viewport_y": 912, "party_x": 160, "party_y": 112,
		"world_x": 1024, "world_y": 1024, "previous_x": 1024, "previous_y": 1024, "direction_word": 0, "walk_phase_word": 0,
		"leader_frame_offset_word": 0, "party_frame_offset_word": 0,
		"member_last": 0, "follower_count": 0}
	var frame_state := {"globals": globals,
		"party_trail": [{"x": 1024, "y": 1024, "direction_word": 0},
			{"x": 1024, "y": 1024, "direction_word": 0}, {"x": 1024, "y": 1024, "direction_word": 0},
			{"x": 1024, "y": 1024, "direction_word": 0}, {"x": 1024, "y": 1024, "direction_word": 0}],
		"party_records": [{"role_id": 0, "x": 160, "y": 112, "current_frame": 3}]}

	# Frame 1: right newly pressed.
	var direction: Dictionary = input.resolve([0, 0, 0, 2, 0, 0, 0, 0], [0, 1, 2, 3, 4, 5, 6, 7])
	check(direction.get("direction_x") == 1 and direction.get("direction_y") == 0,
		"the frame resolves a newly pressed right")
	var iso: Dictionary = input.convert_to_isometric(direction.direction_x, direction.direction_y)
	check(iso.get("direction_x") == 1 and iso.get("direction_y") == 1,
		"the isometric conversion produces the down-right diagonal")
	var intent: Dictionary = input.probe_and_prepare(
		{"x": globals.party_x, "y": globals.party_y},
		{"x": globals.viewport_x, "y": globals.viewport_y},
		iso.direction_x, iso.direction_y, probe)
	check(intent.get("pending_steps") == 1 and intent.get("delta_x") == 16 and intent.get("delta_y") == 8,
		"the probe accepts the step over free ground with 16/8 deltas")
	var faced: Dictionary = facing.answer({"kind": "face_party_toward",
		"state": {"globals":globals}, "delta_x": intent.delta_x, "delta_y": intent.delta_y})
	check(not faced.has("error") and faced.state.globals.direction_word == 3,
		"the recovered extf faces the party along the diagonal: "
			+ str(faced.state.globals.direction_word))
	globals = faced.state.globals
	globals.viewport_x += intent.delta_x; globals.viewport_y += intent.delta_y
	frame_state.globals = globals
	var post: Dictionary = facing.answer({"kind": "post_move_update", "state": frame_state})
	check(not post.has("error") and post.state.globals.world_x == 1040
		and post.state.globals.world_y == 1032,
		"the recovered world relation moves the party to 1040,1032: " + str(post.get("error", ""))
			+ " world=%s,%s" % [str(post.state.globals.world_x), str(post.state.globals.world_y)])
	globals = post.state.globals

	# Frame 2: no keys held - the loop prepares no movement.
	var idle: Dictionary = input.resolve([0, 0, 0, 0, 0, 0, 0, 0], [0, 1, 2, 3, 4, 5, 6, 7])
	check(idle.get("direction_x") == 0 and idle.get("direction_y") == 0,
		"the idle frame resolves no direction")
	var idle_iso: Dictionary = input.convert_to_isometric(idle.direction_x, idle.direction_y)
	var idle_intent: Dictionary = input.probe_and_prepare(
		{"x": globals.party_x, "y": globals.party_y},
		{"x": globals.viewport_x, "y": globals.viewport_y},
		idle_iso.direction_x, idle_iso.direction_y, probe)
	check(idle_intent.get("pending_steps") == 0,
		"an idle frame prepares no movement regardless of the previous direction")

	var output: Dictionary = {"suite": "test_pal98_frame_move", "scope":"component harness with explicit trail/frame doubles; no clamp or hardware loop", "checks": checks,
		"passed": checks.size() - failed, "failed": failed}
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n"); file.close()
	print("PASS %d/%d" % [checks.size() - failed, checks.size()])
	quit(1 if failed > 0 else 0)
