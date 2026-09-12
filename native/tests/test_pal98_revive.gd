# SPDX-License-Identifier: MIT
extends SceneTree
## 0x0022 revive: a zero A0 reads the context party slot, a nonzero A0
## traverses 0..member_last, and A1 above ten is taken as ten. Dead members
## only: HP becomes (MaxHP / 10) * A1 floored at one, poison ids clear while
## scripts stay, statuses below 999 clear, G0302 takes the VB truth, and a
## checked overflow applies nothing.
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

func _state(kernel, member_last: int) -> Dictionary:
	var globals: Dictionary = {"current_scene": 1, "battle_mode": 0, "member_last": member_last,
		"follower_count": 0, "trigger_success_word": 0}
	return {"globals": globals, "equipment": kernel.initial_state([0, 1, 3])}

func _dead(state: Dictionary, role: int, max_hp: int) -> void:
	state.equipment.role_words[9 * 6 + role] = 0
	state.equipment.role_words[7 * 6 + role] = max_hp

func _consume(commands, state: Dictionary, a0: int, a1: int, event_id: int) -> Dictionary:
	return commands.consume(state, {"words": [0x0022, a0, a1, 0], "entry": 1, "event_id": event_id})

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

	# MaxHP 55 with A1=1: 55/10 truncates to 5, the revived word is 5.
	var truncate: Dictionary = _state(kernel, 0)
	_dead(truncate, 0, 55)
	var five: Dictionary = _consume(commands, truncate, 1, 1, 0)
	check(not five.has("error") and truncate.equipment.role_words[9 * 6] == 5
		and five.effects[0].changed_total == 5
		and truncate.globals.trigger_success_word == -1,
		"a non-multiple MaxHP truncates before the multiply: " + str(five.get("error", "")))

	# A1 above ten is taken as ten; zero and small negative amounts floor at
	# one after the checked multiply.
	var clamped: Dictionary = _state(kernel, 2)
	_dead(clamped, 1, 55)
	var ten: Dictionary = _consume(commands, clamped, 1, 15, 0)
	check(not ten.has("error") and clamped.equipment.role_words[9 * 6 + 1] == 50,
		"A1=15 is taken as ten: " + str(ten.get("error", "")))
	var floored: Dictionary = _state(kernel, 2)
	_dead(floored, 3, 55)
	var one: Dictionary = _consume(commands, floored, 1, 0, 0)
	check(not one.has("error") and floored.equipment.role_words[9 * 6 + 3] == 1,
		"A1=0 floors the revived HP at one: " + str(one.get("error", "")))
	var negative: Dictionary = _state(kernel, 0)
	_dead(negative, 0, 55)
	negative.equipment.role_words[9 * 6] = 0xFFFF
	var minus: Dictionary = _consume(commands, negative, 1, 0xFFFF, 0)
	check(not minus.has("error") and negative.equipment.role_words[9 * 6] == 1,
		"a signed dead HP with A1=-1 still floors at one: " + str(minus.get("error", "")))

	# A living member contributes nothing and keeps its HP.
	var mixed: Dictionary = _state(kernel, 2)
	_dead(mixed, 1, 55)
	mixed.equipment.role_words[9 * 6] = 7
	mixed.equipment.role_words[7 * 6] = 55
	var walk: Dictionary = _consume(commands, mixed, 1, 1, 0)
	check(not walk.has("error") and walk.effects[0].targets.size() == 1
		and walk.effects[0].targets[0].role == 1
		and mixed.equipment.role_words[9 * 6] == 7,
		"the traversal revives only the dead member: " + str(walk.get("error", "")))

	# A zero A0 reads the context slot; an outside context is refused.
	var context: Dictionary = _state(kernel, 2)
	_dead(context, 3, 90)
	var by_context: Dictionary = _consume(commands, context, 0, 2, 2)
	check(not by_context.has("error") and by_context.effects[0].targets[0].slot == 2
		and context.equipment.role_words[9 * 6 + 3] == 18,
		"the zero A0 revives the context slot only: " + str(by_context.get("error", "")))
	var outside: Dictionary = _consume(commands, _state(kernel, 2), 0, 1, 5)
	check(outside.get("diagnostic", {}).get("code") == "role_backing",
		"a context outside the projection is refused")

	# Poison ids clear, scripts survive; statuses below 999 clear and the
	# 999 boundary and above stay.
	var backing: Dictionary = _state(kernel, 0)
	_dead(backing, 0, 50)
	backing.equipment.party_poisons[0].encode_u16(0 * 4, 12); backing.equipment.party_poisons[0].encode_u16(0 * 4 + 2, 77)
	backing.equipment.party_poisons[0].encode_u16(15 * 4, 13); backing.equipment.party_poisons[0].encode_u16(15 * 4 + 2, 78)
	backing.equipment.party_statuses[0][0] = 998
	backing.equipment.party_statuses[0][1] = 999
	backing.equipment.party_statuses[0][2] = 1000
	backing.equipment.party_statuses[0][15] = 5
	var cleared: Dictionary = _consume(commands, backing, 1, 2, 0)
	check(not cleared.has("error") and backing.equipment.party_poisons[0].decode_u16(0) == 0
		and backing.equipment.party_poisons[0].decode_u16(2) == 77
		and backing.equipment.party_poisons[0].decode_u16(60) == 0
		and backing.equipment.party_poisons[0].decode_u16(62) == 78,
		"the revive clears every poison id and keeps every script: " + str(cleared.get("error", "")))
	check(backing.equipment.party_statuses[0][0] == 0 and backing.equipment.party_statuses[0][15] == 0
		and backing.equipment.party_statuses[0][1] == 999 and backing.equipment.party_statuses[0][2] == 1000,
		"statuses below 999 clear while 999 and 1000 stay")

	# Traversal stops at member_last: a dead role outside the active range
	# stays untouched.
	var ranged: Dictionary = _state(kernel, 1)
	_dead(ranged, 3, 55)
	ranged.equipment.role_words[9 * 6 + 1] = 0
	ranged.equipment.role_words[7 * 6 + 1] = 55
	var stopped: Dictionary = _consume(commands, ranged, 1, 1, 0)
	check(not stopped.has("error") and stopped.effects[0].targets.size() == 1
		and ranged.equipment.role_words[9 * 6 + 3] == 0,
		"the traversal covers exactly 0..member_last")

	# Checked arithmetic: a negative MaxHP times a large negative A1 overflows
	# the checked multiply, and a running total out of I2 range refuses the
	# whole command; both keep every member's old backing.
	var amount_over: Dictionary = _state(kernel, 0)
	_dead(amount_over, 0, 0x8000)
	amount_over.equipment.role_words[9 * 6] = 0
	var over_run: Dictionary = _consume(commands, amount_over, 1, 0x8000, 0)
	check(over_run.has("error") and str(over_run.error).contains("I2"),
		"the revive amount overflow is refused: " + str(over_run.get("error", "")))
	check(amount_over.equipment.role_words[9 * 6] == 0
		and amount_over.equipment.party_poisons[0].decode_u16(0) == 0
		and amount_over.globals.trigger_success_word == 0,
		"the refused revive applies no member and keeps the success word")
	var total_over: Dictionary = _state(kernel, 1)
	_dead(total_over, 0, 32760); _dead(total_over, 1, 32760)
	var total_before: Dictionary = total_over.duplicate(true)
	var total_run: Dictionary = _consume(commands, total_over, 1, 10, 0)
	check(total_run.get("diagnostic", {}).get("code") == "checked_i2",
		"the running total overflow is refused: " + str(total_run.get("error", "")))
	check(total_over.equipment.role_words[9 * 6] == 0 and total_over.equipment.role_words[9 * 6 + 1] == 0
		and total_over == total_before,
		"the failed multi-member revive publishes no candidate")
	var unchanged: Dictionary = _state(kernel, 0)
	unchanged.equipment.role_words[9 * 6] = 4
	var alive: Dictionary = _consume(commands, unchanged, 1, 3, 0)
	check(not alive.has("error") and alive.effects[0].changed_total == 0
		and unchanged.globals.trigger_success_word == 0,
		"a party with no dead member writes success 0 and nothing else")

	var output: Dictionary = {"suite": "test_pal98_revive", "checks": results,
		"passed": results.size() - failed, "failed": failed}
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n"); file.close()
	print("PASS %d/%d" % [results.size() - failed, results.size()])
	quit(1 if failed > 0 else 0)
