# SPDX-License-Identifier: MIT
extends SceneTree
## DSA-R05 guard: 0x001D reads its zero-A0 target from the passed event context,
## traverses the active members for a nonzero A0, uses the DATA3 field*6+role
## vitals layout with independent clamps, and never partially applies a failing
## multi-target change.
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

func _set_vitals(equipment: Dictionary, role: int, hp: int, mp: int, hp_max: int, mp_max: int) -> void:
	equipment.role_words[9 * 6 + role] = hp
	equipment.role_words[10 * 6 + role] = mp
	equipment.role_words[7 * 6 + role] = hp_max
	equipment.role_words[8 * 6 + role] = mp_max

func _consume(commands, state: Dictionary, a0: int, a1: int, event_id: int) -> Dictionary:
	return commands.consume(state, {"words": [0x001D, a0, a1, 0], "entry": 1, "event_id": event_id})

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

	# Review repro: role0 vitals at WORD54/60 with maxima 42/48, delta +3 gives
	# HP 6, MP 5 and a changed total of 4 (single active member).
	var state: Dictionary = _state(kernel, 0)
	_set_vitals(state.equipment, 0, 3, 4, 6, 5)
	var changed = _consume(commands, state, 1, 3, 0)
	check(not changed.has("error") and changed.effects[0].changed_total == 4
		and state.equipment.role_words[54] == 6 and state.equipment.role_words[60] == 5
		and state.globals.trigger_success_word == -1,
		"the reviewed vitals case lands on field*6+role words 54/60: " + str(changed.get("error", "")))

	# A zero A0 reads the passed event context, not a global and not slot 0.
	var context_state: Dictionary = _state(kernel, 2)
	_set_vitals(context_state.equipment, 0, 11, 11, 20, 20)
	_set_vitals(context_state.equipment, 1, 10, 10, 20, 20)
	var by_context = _consume(commands, context_state, 0, 2, 1)
	check(not by_context.has("error")
		and context_state.equipment.role_words[9 * 6 + 1] == 12
		and context_state.equipment.role_words[9 * 6] == 11,
		"the zero A0 targets the event context slot only: " + str(by_context.get("error", "")))

	# The context drives the slot even without the unbound current-role global,
	# and a context outside the projection is a named failure.
	var bare: Dictionary = _state(kernel, 2)
	_set_vitals(bare.equipment, 3, 7, 7, 20, 20)
	var bare_run = _consume(commands, bare, 0, 1, 2)
	check(not bare_run.has("error") and bare.equipment.role_words[9 * 6 + 3] == 8,
		"the context works without the current-role global: " + str(bare_run.get("error", "")))
	var outside = _consume(commands, _state(kernel, 2), 0, 1, 5)
	check(outside.has("error"), "a context outside the projection is refused")

	# A nonzero A0 traverses exactly the active members 0..member_last.
	var traverse: Dictionary = _state(kernel, 1)
	_set_vitals(traverse.equipment, 0, 5, 5, 50, 50)
	_set_vitals(traverse.equipment, 1, 5, 5, 50, 50)
	_set_vitals(traverse.equipment, 3, 5, 5, 50, 50)
	var walked = _consume(commands, traverse, 1, 4, 0)
	check(not walked.has("error") and walked.effects[0].targets.size() == 2
		and traverse.equipment.role_words[9 * 6 + 3] == 5,
		"the traversal covers members 0..member_last and stops there: " + str(walked.get("error", "")))
	var too_many = _consume(commands, _state(kernel, 4), 1, 1, 0)
	check(too_many.has("error"), "a member count beyond the projection is refused, not clamped")

	# A dead target is skipped without touching the success word of the living.
	var dead: Dictionary = _state(kernel, 0)
	_set_vitals(dead.equipment, 0, 0, 4, 6, 5)
	var dead_run = _consume(commands, dead, 1, 3, 0)
	check(not dead_run.has("error") and dead_run.effects[0].changed_total == 0
		and dead.globals.trigger_success_word == 0,
		"a non-living member is skipped and G0302 stays zero")

	# Checked arithmetic: an I2 overflow on any member fails the whole command
	# and leaves every member untouched.
	var overflow: Dictionary = _state(kernel, 1)
	_set_vitals(overflow.equipment, 0, 100, 10, 200, 20)
	_set_vitals(overflow.equipment, 1, 32000, 10, 33000, 20)
	var overflow_run = _consume(commands, overflow, 1, 1000, 0)
	check(overflow_run.has("error") and str(overflow_run.error).contains("I2"),
		"an I2 overflow fails the command: " + str(overflow_run.get("error", "")))
	check(overflow.equipment.role_words[9 * 6] == 100 and overflow.equipment.role_words[9 * 6 + 1] == 32000,
		"the failed multi-target change applies no member")

	# Both resulting vitals fit I2, but their absolute change total (40000) does
	# not. The original checks the accumulator, not merely the new HP and MP.
	var total_overflow: Dictionary = _state(kernel, 0)
	_set_vitals(total_overflow.equipment, 0, 20000, 20000, 30000, 30000)
	total_overflow.globals.trigger_success_word = -1
	var total_before: Dictionary = total_overflow.duplicate(true)
	var total_run = _consume(commands, total_overflow, 1, 45536, 0)
	check(total_run.get("diagnostic", {}).get("code") == "checked_i2"
		and not total_run.has("state") and total_overflow == total_before,
		"a 40000 absolute change total fails atomically and preserves the prior success word")
	var abs_overflow: Dictionary = _state(kernel, 0)
	_set_vitals(abs_overflow.equipment, 0, 1, 0x8000, 1, 100)
	var abs_before: Dictionary = abs_overflow.duplicate(true)
	var abs_run = _consume(commands, abs_overflow, 1, 0, 0)
	check(abs_run.get("diagnostic", {}).get("code") == "checked_i2" and abs_overflow == abs_before,
		"Abs(-32768) fails without publishing the otherwise clamped MP")
	var across_members: Dictionary = _state(kernel, 1)
	_set_vitals(across_members.equipment, 0, 10000, 10000, 20000, 20000)
	_set_vitals(across_members.equipment, 1, 10000, 10000, 20000, 20000)
	var members_before: Dictionary = across_members.duplicate(true)
	var members_run = _consume(commands, across_members, 1, 55536, 0)
	check(members_run.get("diagnostic", {}).get("code") == "checked_i2" and across_members == members_before,
		"a later member overflowing the total leaves all earlier candidate changes unapplied")
	var boundary: Dictionary = _state(kernel, 0)
	_set_vitals(boundary.equipment, 0, 16384, 16383, 20000, 20000)
	var boundary_run = _consume(commands, boundary, 1, 49152, 0)
	check(not boundary_run.has("error") and boundary_run.effects[0].changed_total == 32767
		and boundary_run.effects[0].success_word == -1,
		"the largest signed change total 32767 remains valid and returns the original true word -1")
	var unchanged: Dictionary = _state(kernel, 0)
	_set_vitals(unchanged.equipment, 0, 6, 5, 6, 5)
	unchanged.globals.trigger_success_word = -1
	var unchanged_run = _consume(commands, unchanged, 1, 3, 0)
	check(not unchanged_run.has("error") and unchanged_run.effects[0].changed_total == 0
		and unchanged.globals.trigger_success_word == 0,
		"a living target already at both maxima clears G0302 to zero")

	var passed = results.filter(func(r): return r.passed).size()
	var out = FileAccess.open(args[1], FileAccess.WRITE)
	if out == null: quit(2); return
	out.store_string(JSON.stringify({"passed": passed, "failed": failed, "checks": results}, "\t"))
	out.close()
	print("vitals context: ", results.size(), " checks, ", failed, " failed")
	quit(0 if failed == 0 else 1)
