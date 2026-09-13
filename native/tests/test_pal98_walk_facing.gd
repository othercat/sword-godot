# SPDX-License-Identifier: MIT
extends SceneTree
## PALOLD ordinal-44 extf and its table are pinned by hash. Lattice checks
## exercise 0070/007A/007B with explicit trail/member/frame doubles. The
## position/phase relation is recovered; the G0464 step signs remain inferred
## until the original initializer and ordinary frame execution are verified.
const Commands = preload("res://src/native_pal98_script_commands.gd")
const Facing = preload("res://src/native_pal98_walk_facing.gd")
const Package = preload("res://src/native_package.gd")

var checks: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

## No-op dependencies are confined to this lattice test, not production.
class EffectsDouble:
	func answer(request: Dictionary) -> Dictionary:
		if request.kind == "sync_party_formation_and_frames":
			return {"completed": true, "party_records": request.state.party_records.duplicate(true)}
		return {"completed": true, "state": request.state.duplicate(true)}

## Pinned original identities for the recovered facing rule.
const EXTF_BODY_SHA256 = "16be3762663cec8c24ad757b6eafdb5796b6de4cf172f039ca271faecc4e702c"
const DIRECTION_TABLE_SHA256 = "5418a11928803f449f1bb4b4ca3fe8865c1ebf6c3c30a06d1b81ae9d1d26fdb8"

func _state() -> Dictionary:
	# The documented original opening: world (1024,1024) = viewport (864,912)
	# plus the (160,112) party anchor.
	return {"globals": {"current_scene": 1, "battle_mode": 0, "day_night_word": 0,
		"fade_gate_word": 0, "member_last": 0, "follower_count": 0, "trigger_success_word": 0,
		"party_x": 160, "party_y": 112, "viewport_x": 864, "viewport_y": 912,
		"world_x": 1024, "world_y": 1024, "previous_x": 1024, "previous_y": 1024,
		"previous_viewport_x": 864, "previous_viewport_y": 912, "direction_word": 0},
		"party_records": [{"role_id": 0, "x": 160, "y": 112, "current_frame": 3}],
		"party_trail": [{"x": 1024, "y": 1024, "direction_word": 0},
			{"x": 1024, "y": 1024, "direction_word": 0}, {"x": 1024, "y": 1024, "direction_word": 0},
			{"x": 1024, "y": 1024, "direction_word": 0}, {"x": 1024, "y": 1024, "direction_word": 0}]}

func _drive(commands, facing, state: Dictionary, words: Array) -> Dictionary:
	var run: Dictionary = commands.consume(state, {"words": words, "entry": 1, "event_id": 0})
	for guard in range(4096):
		if run.has("error"): return {"error": run.error}
		if not run.has("pending"): return {"run": run, "state": state}
		for request in run.get("requests", []):
			# Raw command requests carry no relay state; the facing owner needs
			# the live globals to answer face and post-move kinds.
			if not request.has("state"): request.state = state
			var answer: Dictionary = facing.answer(request)
			if answer.has("error"): return {"error": answer.error}
			if answer.get("state") is Dictionary: state = answer.state
		run = commands.continue_command(run.pending, state)
	return {"error": "walk drive budget exceeded"}

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]) or DirAccess.dir_exists_absolute(args[1]): quit(2); return
	var package = Package.new()
	if not package.load_package(args[0]): push_error("package rejected: " + str(package.error)); quit(2); return
	var commands = Commands.new()
	if not commands.load_source(package.pal98_sources): push_error("commands load failed"); quit(2); return
	var facing = Facing.new(); facing.bind_fallback(EffectsDouble.new()); facing.bind_member_sync(EffectsDouble.new())
	check(Facing.EXTF_BODY_SHA256 == EXTF_BODY_SHA256
		and Facing.DIRECTION_TABLE_SHA256 == DIRECTION_TABLE_SHA256,
		"the facing owner pins the recovered PALOLD extf body and direction table")

	# The exhaustive sign-combo mapping of the decoded table.
	var expected: Array = [[-1, -1, 1], [0, -1, 2], [1, -1, 2], [-1, 0, 1], [1, 0, 3],
		[-1, 1, 0], [0, 1, 0], [1, 1, 3]]
	var mapping_ok: bool = true
	for row in expected:
		var faced: Dictionary = facing.face(row[0], row[1])
		if faced.get("direction") != row[2]: mapping_ok = false
	check(mapping_ok, "the sign-combo mapping matches the decoded direction table")
	check(facing.face(0, 0).get("unchanged") == true,
		"a zero delta writes no direction, like the original index-4 case")

	# The recovered PostMoveUpdate: U2 world relation, movement-driven phase
	# and frame offsets, and the pre-move world into the newest trail entry.
	var mover = Facing.new(); mover.bind_fallback(EffectsDouble.new()); mover.bind_member_sync(EffectsDouble.new())
	var mstate: Dictionary = _state()
	mstate.globals.viewport_x = 65500
	var request: Dictionary = {"kind": "post_move_update", "state": mstate}
	var moved: Dictionary = mover.answer(request)
	check(not moved.has("error") and moved.state.globals.world_x == 124
		and moved.state.globals.world_y == 1024,
		"the world relation wraps through U2 like the recovered body: %d,%d"
			% [moved.state.globals.world_x, moved.state.globals.world_y])
	check(moved.state.globals.walk_phase_word == 1 and moved.state.globals.leader_frame_offset_word == 1
		and moved.state.globals.party_frame_offset_word == 2,
		"a movement step advances the WalkPhase and frame offsets")
	check(moved.state.party_trail[0].x == 1024 and moved.state.party_trail[0].y == 1024,
		"the explicit trail test double retains its input")
	var moved2: Dictionary = mover.answer({"kind": "post_move_update", "state": moved.state})
	check(moved2.state.globals.walk_phase_word == 2 and moved2.state.globals.leader_frame_offset_word == 0,
		"the second movement step lands on the even phase with zero offsets")
	moved2.state.globals.previous_x = moved2.state.globals.world_x
	moved2.state.globals.previous_y = moved2.state.globals.world_y
	var still: Dictionary = mover.answer({"kind": "post_move_update", "state": moved2.state})
	check(still.state.globals.walk_phase_word == 0 and still.state.globals.leader_frame_offset_word == 0,
		"a stationary step folds the phase back to zero")

	# Walk closure: with the corrected G0464 pairing, every lattice walk lands
	# exactly on its tile-derived target at every speed. The step-table signs
	# are derived, not guessed: of the 24 possible sign assignments, exactly
	# one closes the decoded extf loop on all isometric lattice states.
	var converged: int = 0; var broken: int = 0
	var broken_sample: String = ""
	for arg0 in range(-4, 5):
		for arg1 in range(-4, 5):
			for arg2 in range(0, 2):
				for speed in [2, 4, 8]:
					var encoded: Array = [{2: 0x0070, 4: 0x007A, 8: 0x007B}[speed],
						(arg0 + 65536) & 0xFFFF, (arg1 + 65536) & 0xFFFF, (arg2 + 65536) & 0xFFFF]
					var state: Dictionary = _state()
					var run: Dictionary = _drive(commands, facing, state, encoded)
					var target_x: int = (arg0 * 2 + arg2) * 16
					var target_y: int = (arg1 * 2 + arg2) * 8
					var at: bool = not run.has("error") \
						and run.state.globals.world_x == target_x \
						and run.state.globals.world_y == target_y
					if run.has("error"):
						broken += 1
						if broken_sample.is_empty(): broken_sample = str(run.error) + " args=%d,%d,%d s=%d world=%d,%d" % [arg0, arg1, arg2, speed, run.state.globals.world_x, run.state.globals.world_y]
					elif at: converged += 1
					else:
						broken += 1
						if broken_sample.is_empty(): broken_sample = "world %d,%d" % [run.state.globals.world_x, run.state.globals.world_y]
	check(broken == 0,
		"every lattice walk lands exactly on its tile-derived target: %d broken %s" % [broken, broken_sample])
	check(converged == 486, "all 486 lattice/speed walks converge: %d" % converged)

	# The owner refuses foreign kinds instead of acknowledging them.
	var foreign: Dictionary = facing.answer({"kind": "play_midi"})
	check(foreign.has("error"), "a foreign audio kind is refused by name")

	var output: Dictionary = {"suite": "test_pal98_walk_facing", "checks": checks,
		"passed": checks.size() - failed, "failed": failed}
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n"); file.close()
	print("PASS %d/%d" % [checks.size() - failed, checks.size()])
	quit(1 if failed > 0 else 0)
