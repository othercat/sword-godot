# SPDX-License-Identifier: MIT
extends SceneTree
## DSA-R06/R07 guard: 0x007F takes its round count from A2, restores from
## (0,0,-1), and runs one round per host interaction so each round continues
## from the state the host wrote back - never from a precomputed queue.
const Commands = preload("res://src/native_pal98_script_commands.gd")
const Equipment = preload("res://src/native_pal98_equipment_kernel.gd")
const Package = preload("res://src/native_package.gd")

var results: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	results.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _zero(count: int) -> PackedByteArray:
	var bytes = PackedByteArray(); bytes.resize(count); return bytes

func _state(kernel) -> Dictionary:
	var globals: Dictionary = {"current_scene": 1, "battle_mode": 0, "member_last": 2,
		"follower_count": 0, "world_x": 1024, "world_y": 1024,
		"viewport_x": 864, "viewport_y": 912, "party_x": 160, "party_y": 112,
		"previous_viewport_x": 864, "previous_viewport_y": 912}
	var records: Array = []
	for slot in range(5):
		records.append({"role_id": 0, "screen_x": 160 + slot * 16, "screen_y": 112 - slot * 8,
			"current_frame": 3})
	return {"globals": globals, "equipment": kernel.initial_state([0, 1, 3]),
		"party_records": records}

func _consume(commands, state: Dictionary, words: Array) -> Dictionary:
	return commands.consume(state, {"words": words, "entry": 1, "event_id": 0})

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]) or DirAccess.dir_exists_absolute(args[1]): quit(2); return
	var package = Package.new()
	if not package.load_package(args[0]): push_error("package rejected: " + str(package.error)); quit(2); return
	var kernel = Equipment.new()
	kernel.read_tables(package.pal98_sources.copy_chunk("data", 3),
		package.pal98_sources.copy_chunk("sss", 2), package.pal98_sources.copy_chunk("sss", 4))
	var commands = Commands.new()
	if not commands.load_source(package.pal98_sources): push_error("commands load failed"); quit(2); return

	# R06 repro: [007F,2,0,3] pans by +2 for A2=3 rounds: 864 -> 870, one round
	# per host interaction.
	var state: Dictionary = _state(kernel)
	var moved = _consume(commands, state, [0x007F, 2, 0, 3])
	check(not moved.has("error"), "the three-round pan is accepted: " + str(moved.get("error", "")))
	check(moved.effects.size() == 1 and moved.effects[0].viewport_x == 866
		and moved.effects[0].round == 1 and moved.get("pending") != null,
		"round one publishes 866 with a pending plan")
	var rounds_x: Array = [moved.effects[0].viewport_x]
	var plan: Variant = moved.pending
	while plan != null and not (plan is Dictionary and plan.is_empty()):
		var step = commands.continue_command(plan, state)
		if step.has("error"):
			check(false, "a round continues: " + str(step.get("error", ""))); break
		if not step.get("effects", []).is_empty():
			rounds_x.append(step.effects[0].viewport_x)
		plan = step.get("pending")
	check(rounds_x == [866, 868, 870],
		"each round records its own viewport: " + str(rounds_x))
	check(state.globals.viewport_x == 870 and state.globals.previous_viewport_x == 868,
		"the final viewport is 870 and the previous copy is 868")

	# R06 repro: [007F,0,0,FFFF] restores the world-derived viewport and anchor.
	var restore_state: Dictionary = _state(kernel)
	restore_state.globals.world_x = 1200; restore_state.globals.world_y = 1300
	restore_state.globals.viewport_x = 500; restore_state.globals.viewport_y = 500
	var restored = _consume(commands, restore_state, [0x007F, 0, 0, 0xFFFF])
	check(not restored.has("error") and restored.effects[0].kind == "viewport_restore"
		and restore_state.globals.viewport_x == 1040 and restore_state.globals.viewport_y == 1188
		and restore_state.globals.party_x == 160 and restore_state.globals.party_y == 112,
		"the (0,0,-1) form restores viewport (1040,1188) and anchor (160,112): "
			+ str(restored.get("error", "")))
	check(restored.get("requests", []).map(func(r): return r.kind).has("render_current_map_background")
		and restored.get("pending") == null,
		"the restore renders the background and carries no round pending")

	# A negative non-restore A2 runs one absolute round: viewport (A0*32-160, A1*16-112).
	var absolute_state: Dictionary = _state(kernel)
	var absolute = _consume(commands, absolute_state, [0x007F, 30, 60, 0xFFFE])
	check(not absolute.has("error") and absolute.effects.size() == 1
		and absolute.effects[0].mode == "absolute"
		and absolute_state.globals.viewport_x == 30 * 32 - 160
		and absolute_state.globals.viewport_y == 60 * 16 - 112,
		"the absolute form sets (A0*32-160, A1*16-112) once: " + str(absolute.get("error", "")))

	# A zero A2 re-anchors once and writes A2 back as -1 (visible in the mode).
	var reanchor_state: Dictionary = _state(kernel)
	reanchor_state.globals.viewport_x = 500; reanchor_state.globals.viewport_y = 500
	var reanchored = _consume(commands, reanchor_state, [0x007F, 5, 7, 0])
	check(not reanchored.has("error") and reanchored.effects.size() == 1
		and reanchored.effects[0].mode == "reanchor"
		and reanchor_state.globals.party_x == 160 and reanchor_state.globals.party_y == 112
		and reanchor_state.globals.viewport_x == 864 and reanchor_state.globals.viewport_y == 912,
		"the zero-A2 form re-anchors once at (160,112): " + str(reanchored.get("error", "")))

	# R07: the second round must read the state the host wrote back. A real frame
	# event may move the viewport between rounds; precomputing both rounds from
	# the first state would publish 870 instead of the written-back 902.
	var live: Dictionary = _state(kernel)
	var first = _consume(commands, live, [0x007F, 2, 0, 2])
	check(not first.has("error") and first.effects[0].viewport_x == 866
		and first.pending != null and first.pending.get("viewport") is Dictionary,
		"the multi-round pan publishes round one with a pending plan")
	check(first.requests.map(func(r): return r.kind) == ["start_frame_and_process_events",
		"update_viewport_and_party_position", "render_scene_frame"],
		"round one requests the frame, update and render in original order")
	# The host processes the frame and its events move the viewport.
	live.globals.viewport_x = 900
	var second = commands.continue_command(first.pending, live)
	check(not second.has("error") and second.effects.size() == 1
		and second.effects[0].viewport_x == 902 and second.effects[0].round == 2,
		"round two continues from the written-back viewport: " + str(second.get("error", "")))
	check(second.get("pending") == null and second.get("rounds") == 2,
		"the machine reports its terminal round count: " + str(second))

	# An unknown continuation shape is a named error. A spent plan re-continues
	# only to a terminal receipt with no effects; receipt identity itself is
	# enforced by the relay layer's request ids.
	var unknown = commands.continue_command({"walk": {}}, live)
	check(unknown.has("error"), "a foreign pending shape is refused")
	var spent = commands.continue_command(first.pending, live)
	check(not spent.has("error") and spent.get("effects", []).is_empty()
		and spent.get("requests", []).is_empty() and spent.get("pending") == null,
		"a spent plan only yields an empty terminal receipt")

	# The member shift covers exactly members 1..member_last of the fixed backing.
	var narrow: Dictionary = _state(kernel)
	narrow.globals.member_last = 1
	var narrow_moved = _consume(commands, narrow, [0x007F, 0, 0, 1])
	check(not narrow_moved.has("error") and narrow_moved.effects[0].members_shifted == 1,
		"the shift loop covers members 1..member_last: " + str(narrow_moved.effects[0].members_shifted))

	var passed = results.filter(func(r): return r.passed).size()
	var out = FileAccess.open(args[1], FileAccess.WRITE)
	if out == null: quit(2); return
	out.store_string(JSON.stringify({"passed": passed, "failed": failed, "checks": results}, "\t"))
	out.close()
	print("viewport move: ", results.size(), " checks, ", failed, " failed")
	quit(0 if failed == 0 else 1)
