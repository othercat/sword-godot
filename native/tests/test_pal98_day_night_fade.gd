# SPDX-License-Identifier: MIT
extends SceneTree
## 0x0080 day/night fade: copymen saves the active window, 32 cvpate rounds
## converge the work area toward the opposite block with the native +2/-1
## byte rule, each round publishes an install plus event/frame (A0<=0) or
## wtime (A0>0) requests, later rounds read the state the host wrote back,
## and the terminal adopts the target offset, installs the target block and
## clears G0250.
const Commands = preload("res://src/native_pal98_script_commands.gd")
const Package = preload("res://src/native_package.gd")

var results: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	results.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _zero(count: int) -> PackedByteArray:
	var bytes = PackedByteArray(); bytes.resize(count); return bytes

func _palette_bytes() -> PackedByteArray:
	var bytes: PackedByteArray = _zero(0x780)
	for index in range(0x180, 0x300): bytes[index] = 63  # night block; day stays zero
	return bytes

func _state(day_night: int) -> Dictionary:
	return {"globals": {"current_scene": 1, "battle_mode": 0, "day_night_word": day_night,
		"fade_gate_word": 1, "member_last": 0, "follower_count": 0, "trigger_success_word": 0},
		"palette_bytes": _palette_bytes()}

func _consume(commands, state: Dictionary, arg0: int) -> Dictionary:
	return commands.consume(state, {"words": [0x0080, arg0, 0, 0], "entry": 1, "event_id": 0})

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]) or DirAccess.dir_exists_absolute(args[1]): quit(2); return
	var package = Package.new()
	if not package.load_package(args[0]): push_error("package rejected: " + str(package.error)); quit(2); return
	var commands = Commands.new()
	if not commands.load_source(package.pal98_sources): push_error("commands load failed"); quit(2); return

	# Backing refusals keep the caller's state.
	var bare: Dictionary = _state(0)
	bare.globals.day_night_word = 0x181
	var refused: Dictionary = _consume(commands, bare, 0)
	check(refused.get("diagnostic", {}).get("code") == "palette_state",
		"a day/night offset beyond 0x180 is refused: " + str(refused.get("error", "")))
	var thin: Dictionary = _state(0)
	thin.palette_bytes = thin.palette_bytes.slice(0, 0x77F)
	var short: Dictionary = _consume(commands, thin, 0)
	check(short.get("diagnostic", {}).get("code") == "palette_backing",
		"a short palette buffer is refused")

	# Day to night with the wait branch: 32 install+wait rounds, a work byte
	# rising by 2 per round past the target, then the terminal adopting the
	# night offset, installing the night block and clearing the fade gate.
	var night: Dictionary = _state(0)
	var run: Dictionary = _consume(commands, night, 5)
	check(not run.has("error") and run.pending.get("day_night_fade") is Dictionary
		and run.effects[0].round == 1 and run.effects[0].moved == 0x300,
		"the fade begins with the whole 0x300 window moving: " + str(run.get("error", "")))
	check(run.requests.size() == 2 and run.requests[0].kind == "apply_palette"
		and run.requests[0].offset == 0x300 and run.requests[1].kind == "fade_wait"
		and run.requests[1].delay == 5,
		"a positive A0 installs and waits each round")
	check(run.requests[0].bytes.size() == 0x300 and run.requests[0].bytes[0] == 2,
		"the first round install carries the +2 advanced work bytes")
	var rounds: int = 1
	while run.has("pending"):
		run = commands.continue_command(run.pending, night)
		rounds += 1
	check(rounds == 32 and run.rounds == 32,
		"the fade runs exactly 32 rounds: " + str(rounds))
	check(night.globals.day_night_word == 0x180 and night.globals.fade_gate_word == 0,
		"the terminal adopts the night offset and clears G0250")
	check(night.palette_bytes[0x300] == 64 and night.palette_bytes[0x180] == 63,
		"the work byte overshoots the 63 target by one exactly as the native +2 rule does")
	check(run.requests.size() == 1 and run.requests[0].offset == 0x180
		and run.requests[0].bytes[0] == 63,
		"the terminal installs the night block itself")
	check(run.effects[run.effects.size() - 1].kind == "day_night_fade_done",
		"the terminal publishes the done effect")

	# Night to day falls by one per round and cannot reach zero within 32
	# rounds; the terminal still installs the day block directly.
	var day: Dictionary = _state(0x180)
	var back: Dictionary = _consume(commands, day, 5)
	var back_rounds: int = 1
	while back.has("pending"):
		back = commands.continue_command(back.pending, day)
		back_rounds += 1
	check(back_rounds == 32 and day.palette_bytes[0x300] == 31
		and day.globals.day_night_word == 0,
		"the reverse fade falls by one per round and lands on the day offset")
	check(back.requests[0].bytes[0] == 0,
		"the terminal installs the day block itself")

	# The A0<=0 branch asks for the event pump and frame helpers each round.
	var pumped: Dictionary = _state(0)
	var soft: Dictionary = _consume(commands, pumped, 0)
	check(soft.requests.size() == 3 and soft.requests[1].kind == "fade_event_pump"
		and soft.requests[2].kind == "fade_frame",
		"a nonpositive A0 pumps events and renders a frame per round")

	# Later rounds read the host-written-back state, not a pre-batched plan.
	var live: Dictionary = _state(0)
	var staged: Dictionary = _consume(commands, live, 5)
	staged = commands.continue_command(staged.pending, live)
	# The host answers round 1 and rewrote a work byte before round 2.
	live.palette_bytes[0x300 + 5] = 63
	var second: Dictionary = commands.continue_command(staged.pending, live)
	check(not second.has("error") and second.effects[0].round == 3
		and second.effects[0].moved == 0x300 - 1,
		"the round after the host writeback skips the settled byte: " + str(second.get("error", "")))
	check(live.palette_bytes[0x300 + 5] == 63,
		"the settled byte stays exactly at its target")

	var output: Dictionary = {"suite": "test_pal98_day_night_fade", "checks": results,
		"passed": results.size() - failed, "failed": failed}
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n"); file.close()
	print("PASS %d/%d" % [results.size() - failed, results.size()])
	quit(1 if failed > 0 else 0)
