# SPDX-License-Identifier: MIT
extends SceneTree
## 0x0046 ffxy: the teleport clamps the two viewport words independently to
## 0..G030A and 0..G030C (PALOLD 0x1000352B) instead of refusing, keeps the
## world and previous words unclamped, and the background request adopts the
## final clamped viewport. Every checked I2 step in the world, subtraction and
## member-position arithmetic fails named and publishes no candidate.
const Commands = preload("res://src/native_pal98_script_commands.gd")
const Package = preload("res://src/native_package.gd")

var results: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	results.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _state() -> Dictionary:
	var globals: Dictionary = {"current_scene": 1, "party_x": 160, "party_y": 112, "direction_word": 0,
		"battle_mode": 0, "ffxy_max_x": 1696, "ffxy_max_y": 1840, "trigger_success_word": 0}
	var records: Array = []
	for slot in range(5): records.append({"role_id": 0, "screen_x": 0, "screen_y": 0, "current_frame": 3})
	var trail: Array = []
	for slot in range(5): trail.append({"x": 0, "y": 0, "direction_word": 0})
	return {"globals": globals, "party_records": records, "party_trail": trail}

func _consume(commands, state: Dictionary, a0: int, a1: int, a2: int) -> Dictionary:
	return commands.consume(state, {"words": [0x0046, a0, a1, a2], "entry": 1, "event_id": 0})

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]) or DirAccess.dir_exists_absolute(args[1]): quit(2); return
	var package = Package.new()
	if not package.load_package(args[0]): push_error("package rejected: " + str(package.error)); quit(2); return
	var commands = Commands.new()
	if not commands.load_source(package.pal98_sources): push_error("commands load failed"); quit(2); return

	# A legal in-bounds teleport keeps both axes and reports no clamp.
	var plain: Dictionary = _state()
	var inside: Dictionary = _consume(commands, plain, 32, 64, 0)
	check(not inside.has("error") and inside.effects[0].viewport_x == 864
		and inside.effects[0].viewport_y == 912 and inside.effects[0].clamped_x == false
		and inside.effects[0].clamped_y == false,
		"an in-bounds teleport keeps the raw viewport: " + str(inside.get("error", "")))
	check(plain.globals.viewport_x == 864 and plain.globals.viewport_y == 912,
		"the globals carry the final viewport words")

	# The northwest corner clamps both axes to zero; the world words stay
	# unclamped at the teleport target.
	var corner: Dictionary = _state()
	var zeroed: Dictionary = _consume(commands, corner, 0, 0, 0)
	check(not zeroed.has("error") and zeroed.effects[0].viewport_x == 0
		and zeroed.effects[0].viewport_y == 0 and zeroed.effects[0].clamped_x == true
		and zeroed.effects[0].clamped_y == true and zeroed.effects[0].world_x == 0,
		"the northwest corner clamps both axes to zero: " + str(zeroed.get("error", "")))

	# One-axis overflow only: an east overflow clamps X to the bound and leaves
	# the legal Y untouched.
	var east: Dictionary = _state()
	east.globals.ffxy_max_x = 800
	var clamped_x: Dictionary = _consume(commands, east, 32, 64, 0)
	check(not clamped_x.has("error") and clamped_x.effects[0].viewport_x == 800
		and clamped_x.effects[0].viewport_y == 912 and clamped_x.effects[0].clamped_x == true
		and clamped_x.effects[0].clamped_y == false,
		"an east overflow clamps only X to 800: " + str(clamped_x.get("error", "")))
	check(east.party_trail[0].x == 160 + 800 and east.party_trail[4].x == 160 + 800 + 4 * 16,
		"the trail entries adopt the clamped viewport")

	# A south overflow clamps only Y.
	var south: Dictionary = _state()
	south.globals.ffxy_max_y = 900
	var clamped_y: Dictionary = _consume(commands, south, 32, 64, 0)
	check(not clamped_y.has("error") and clamped_y.effects[0].viewport_y == 900
		and clamped_y.effects[0].viewport_x == 864 and clamped_y.effects[0].clamped_y == true
		and clamped_y.effects[0].clamped_x == false,
		"a south overflow clamps only Y to 900: " + str(clamped_y.get("error", "")))

	# A raw axis exactly at its bound is in bounds, not clamped.
	var edge: Dictionary = _state()
	edge.globals.ffxy_max_x = 864; edge.globals.ffxy_max_y = 912
	var exact: Dictionary = _consume(commands, edge, 32, 64, 0)
	check(not exact.has("error") and exact.effects[0].clamped_x == false
		and exact.effects[0].clamped_y == false and exact.effects[0].viewport_x == 864,
		"the exact upper bound is inside the clamp range")

	# The background request adopts the final clamped viewport; a battle
	# teleport asks for no replay.
	var replay: Dictionary = _consume(commands, _state(), 0, 0, 0)
	check(replay.requests.size() == 1 and replay.requests[0].kind == "render_current_map_background"
		and replay.requests[0].viewport_x == 0 and replay.requests[0].viewport_y == 0,
		"the background replay carries the clamped viewport")
	var battle: Dictionary = _state()
	battle.globals.battle_mode = 1
	var war: Dictionary = _consume(commands, battle, 0, 0, 0)
	check(not war.has("error") and war.get("requests", []).is_empty(),
		"a battle teleport asks for no background replay")

	# The bounds come from the explicit G030A/G030C globals.
	var bare: Dictionary = _state()
	bare.globals.erase("ffxy_max_x")
	var unbounded: Dictionary = _consume(commands, bare, 32, 64, 0)
	check(unbounded.get("diagnostic", {}).get("code") == "ffxy_bounds",
		"a missing X bound fails named: " + str(unbounded.get("error", "")))
	var negative: Dictionary = _state()
	negative.globals.ffxy_max_y = -1
	var below: Dictionary = _consume(commands, negative, 32, 64, 0)
	check(below.get("diagnostic", {}).get("code") == "ffxy_bounds",
		"a negative bound fails named")

	# Checked I2: the doubling, the scale and the viewport subtraction each
	# refuse their overflow and the caller's state keeps every value.
	var doubled: Dictionary = _state()
	var doubled_run: Dictionary = _consume(commands, doubled, 0x8000, 0, 0)
	check(doubled_run.get("diagnostic", {}).get("code") == "checked_i2"
		and str(doubled_run.error).contains("doubled"),
		"a doubled argument overflow is refused: " + str(doubled_run.get("error", "")))
	var scaled: Dictionary = _state()
	var scaled_run: Dictionary = _consume(commands, scaled, 1024, 64, 0)
	check(scaled_run.get("diagnostic", {}).get("code") == "checked_i2"
		and str(scaled_run.error).contains("world position leaves"),
		"a world scale overflow is refused: " + str(scaled_run.get("error", "")))
	var far_party: Dictionary = _state()
	far_party.globals.party_x = -32768
	var far_before: Dictionary = far_party.duplicate(true)
	var far_run: Dictionary = _consume(commands, far_party, 32, 64, 0)
	check(far_run.get("diagnostic", {}).get("code") == "checked_i2"
		and str(far_run.error).contains("viewport subtraction"),
		"a viewport subtraction overflow is refused: " + str(far_run.get("error", "")))
	check(far_party == far_before, "the refused teleport preserves the caller's state")

	# The member stepping is checked too: a formation step out of I2 range
	# publishes nothing and touches no record or trail slot.
	var crowded: Dictionary = _state()
	crowded.globals.party_x = 32752
	var stepped: Dictionary = _consume(commands, crowded, 1023, 64, 1)
	check(stepped.get("diagnostic", {}).get("code") == "checked_i2"
		and str(stepped.error).contains("formation step"),
		"a formation step overflow is refused: " + str(stepped.get("error", "")))
	check(crowded.party_records[0].screen_x == 0 and crowded.party_trail[0].x == 0,
		"the refused member walk applied no slot")

	var output: Dictionary = {"suite": "test_pal98_teleport_clamp", "checks": results,
		"passed": results.size() - failed, "failed": failed}
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n"); file.close()
	print("PASS %d/%d" % [results.size() - failed, results.size()])
	quit(1 if failed > 0 else 0)
