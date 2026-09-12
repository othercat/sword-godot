# SPDX-License-Identifier: MIT
extends SceneTree
## 0x008C color fade: the active window is saved into the work area and the
## target block, corpate fills the work area with the 3-byte color at the
## 16-bit wrapped offset A0*3, a nonzero A2 swaps the two offsets so the
## gradient runs the other way, and 63 rounds each publish cvpate's install of
## the target block plus a wtime of A1 (only zero defaults to one). No
## day/night write, no gate clear, no extra terminal install.
const Commands = preload("res://src/native_pal98_script_commands.gd")
const Equipment = preload("res://src/native_pal98_equipment_kernel.gd")
const Package = preload("res://src/native_package.gd")

var results: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	results.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _palette_bytes() -> PackedByteArray:
	var bytes = PackedByteArray(); bytes.resize(0xC00)
	for index in range(0x300): bytes[index] = 40  # active window: uniform 40s
	return bytes

func _state(day_night: int) -> Dictionary:
	return {"globals": {"current_scene": 1, "battle_mode": 0, "day_night_word": day_night,
		"fade_gate_word": 1, "member_last": 0, "follower_count": 0, "trigger_success_word": 0},
		"palette_bytes": _palette_bytes()}

func _consume(commands, state: Dictionary, color: int, a1: int, a2: int) -> Dictionary:
	return commands.consume(state, {"words": [0x008C, color, a1, a2], "entry": 1, "event_id": 0})

func _drive(commands, state: Dictionary) -> Dictionary:
	var run: Dictionary = _consume(commands, state, 5, 3, 0)
	var rounds: int = 1
	while run.has("pending"):
		run = commands.continue_command(run.pending, state)
		rounds += 1
	return run

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

	# A uniform window with the color sample inside it: corpate fills the work
	# area with the same 40s, so the first cvpate round moves nothing.
	var plain: Dictionary = _state(0)
	var start: Dictionary = _consume(commands, plain, 5, 3, 0)
	check(not start.has("error") and start.effects[0].round == 1
		and start.effects[0].moved == 0,
		"a uniform window settles the first round: " + str(start.get("error", "")))
	check(plain.palette_bytes[0x600] == 40 and plain.palette_bytes[0x900] == 40,
		"both the work area and the target block start as saved copies of the window")
	var run: Dictionary = start
	var rounds: int = 1
	while run.has("pending"):
		run = commands.continue_command(run.pending, plain)
		rounds += 1
	check(rounds == 63 and run.rounds == 63 and not run.has("pending"),
		"the color fade runs exactly 63 rounds: " + str(rounds))
	check(run.effects[run.effects.size() - 1].round == 63
		and run.effects[run.effects.size() - 1].moved == 0,
		"a uniform palette keeps every round at zero movement")
	check(run.requests.size() == 2 and run.requests[0].kind == "apply_palette"
		and run.requests[0].offset == 0x480 and run.requests[1].kind == "fade_wait"
		and run.requests[1].delay == 3,
		"each round installs the target block and waits A1=3")
	check(plain.globals.day_night_word == 0 and plain.globals.fade_gate_word == 1,
		"the color fade leaves the day/night offset and the gate untouched")

	# Only a zero A1 defaults to one.
	var timed: Dictionary = _consume(commands, _state(0), 5, 0, 0)
	check(not timed.has("error") and timed.requests[1].delay == 1,
		"a zero A1 waits one tick")

	# A nonzero A2 swaps the offsets: the install moves to the work area and
	# the color-filled work block converges toward the saved source.
	var swapped_state: Dictionary = _state(0)
	swapped_state.palette_bytes[15] = 60; swapped_state.palette_bytes[16] = 60; swapped_state.palette_bytes[17] = 60
	var swapped: Dictionary = _consume(commands, swapped_state, 5, 2, 1)
	check(not swapped.has("error") and swapped.requests[0].offset == 0x300,
		"the swapped direction installs the work area block")
	check(swapped_state.palette_bytes[0x900] == 40 and swapped_state.palette_bytes[0x600] == 59,
		"the installed work block converges while the separate saved block stays unchanged")

	# The color sample must stay inside the palette window.
	var outside: Dictionary = _state(0)
	var out_before: Dictionary = outside.duplicate(true)
	var beyond: Dictionary = _consume(commands, outside, 300, 3, 0)
	check(beyond.get("diagnostic", {}).get("code") == "palette_color"
		and str(beyond.error).contains("outside"),
		"a sample past the window is refused: " + str(beyond.get("error", "")))
	var wrapped: Dictionary = _consume(commands, _state(0), 0x8000, 3, 0)
	check(wrapped.get("diagnostic", {}).get("code") == "palette_color",
		"a negative A0 wraps its offset and is refused the same way")
	check(outside == out_before, "the refused color fade preserves the state")
	var last: Dictionary = _consume(commands, _state(0), 255, 3, 0)
	check(not last.has("error"),
		"color 255 samples the last full triple inside the window")

	# The fade coexists with the inventory commands: a following 0x0020 sees
	# the same state object with both backings intact.
	var mixed: Dictionary = _state(0)
	mixed["equipment"] = kernel.initial_state([0])
	mixed.globals.member_last = 0
	mixed["inventory_bytes"] = PackedByteArray(); mixed.inventory_bytes.resize(256 * 6)
	mixed.inventory_bytes.encode_s16(5 * 6, 30); mixed.inventory_bytes.encode_s16(5 * 6 + 2, 4)
	var faded: Dictionary = _drive(commands, mixed)
	var counted: Dictionary = commands.consume(mixed,
		{"words": [0x0020, 30, 6, 9], "entry": 1, "event_id": 0})
	check(not faded.has("pending") and counted.entry == 8 and counted.effects[0].count == 4
		and mixed.palette_bytes.size() == 0xC00,
		"the 0020 count after a color fade sees the same palette state: "
			+ str(counted.get("error", "")))

	var output: Dictionary = {"suite": "test_pal98_color_fade", "checks": results,
		"passed": results.size() - failed, "failed": failed}
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n"); file.close()
	print("PASS %d/%d" % [results.size() - failed, results.size()])
	quit(1 if failed > 0 else 0)
