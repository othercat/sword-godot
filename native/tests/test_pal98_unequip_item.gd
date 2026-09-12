# SPDX-License-Identifier: MIT
extends SceneTree
## 0x0023 unequip: the absolute role A0 (zero-based, possibly outside the
## projection) returns equipped fields to the latest inventory. A1<=0 sweeps
## fields 11..16 and a positive A1 addresses the single checked field 10+A1.
## Only a signed word above zero goes through T140 add (+1) and is cleared; a
## full inventory still clears the field; a checked overflow on any add
## publishes no candidate.
const Commands = preload("res://src/native_pal98_script_commands.gd")
const Equipment = preload("res://src/native_pal98_equipment_kernel.gd")
const Package = preload("res://src/native_package.gd")

var results: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	results.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _inventory_bytes() -> PackedByteArray:
	var bytes = PackedByteArray(); bytes.resize(256 * 6); return bytes

func _put(inventory: PackedByteArray, slot: int, item: int, amount: int) -> void:
	inventory.encode_s16(slot * 6, item); inventory.encode_s16(slot * 6 + 2, amount)

func _state(kernel, member_last: int) -> Dictionary:
	var globals: Dictionary = {"current_scene": 1, "battle_mode": 0, "member_last": member_last,
		"follower_count": 0, "trigger_success_word": 0}
	return {"globals": globals, "equipment": kernel.initial_state([0, 1, 3]),
		"inventory_bytes": _inventory_bytes()}

func _consume(commands, state: Dictionary, role: int, a1: int) -> Dictionary:
	return commands.consume(state, {"words": [0x0023, role, a1, 0], "entry": 1, "event_id": 0})

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

	# A positive A1 addresses 10+A1 exactly: A1=1 returns field 11 of the
	# absolute role 3 and merges +1 into the first living inventory match.
	var single: Dictionary = _state(kernel, 2)
	_put(single.inventory_bytes, 5, 30, 4)
	single.equipment.role_words[11 * 6 + 3] = 30
	var one: Dictionary = _consume(commands, single, 3, 1)
	check(not one.has("error") and one.effects[0].returned.size() == 1
		and one.effects[0].returned[0].field == 11
		and single.inventory_bytes.decode_s16(5 * 6 + 2) == 5
		and single.equipment.role_words[11 * 6 + 3] == 0,
		"A1=1 returns field 11 of absolute role 3 and merges into slot 5: " + str(one.get("error", "")))

	# A1<=0 sweeps 11..16 in order: positive words return, zero and negative
	# words stay untouched. The real DATA3 row of role 1 starts zeroed here so
	# the sweep result is exactly the three fields under test.
	var swept: Dictionary = _state(kernel, 2)
	for field in range(11, 17): swept.equipment.role_words[field * 6 + 1] = 0
	swept.equipment.role_words[12 * 6 + 1] = 7
	swept.equipment.role_words[14 * 6 + 1] = 7
	swept.equipment.role_words[15 * 6 + 1] = 0xFFFF
	swept.equipment.role_words[16 * 6 + 1] = 5
	_put(swept.inventory_bytes, 2, 7, 10); _put(swept.inventory_bytes, 8, 5, 3)
	var all: Dictionary = _consume(commands, swept, 1, 0)
	check(not all.has("error") and all.effects[0].returned.size() == 3
		and all.effects[0].returned[0].field == 12 and all.effects[0].returned[1].field == 14
		and all.effects[0].returned[2].field == 16,
		"the A1=0 sweep returns exactly the three positive fields in order: " + str(all.get("error", "")))
	check(swept.inventory_bytes.decode_s16(2 * 6 + 2) == 12
		and swept.inventory_bytes.decode_s16(8 * 6 + 2) == 4
		and swept.equipment.role_words[15 * 6 + 1] == 0xFFFF
		and swept.equipment.role_words[13 * 6 + 1] == 0,
		"item 7 gains two copies, item 5 one, and the zero/negative words are untouched")

	# A1=7 legitimately reaches field 17; the sweep covers it without a clamp.
	var seventeen: Dictionary = _state(kernel, 2)
	seventeen.equipment.role_words[17 * 6 + 4] = 9
	var deep: Dictionary = _consume(commands, seventeen, 4, 7)
	check(not deep.has("error") and deep.effects[0].returned.size() == 1
		and deep.effects[0].returned[0].field == 17
		and seventeen.inventory_bytes.decode_s16(0 * 6) == 9,
		"A1=7 reaches field 17 and creates an inventory record for item 9: " + str(deep.get("error", "")))

	# Field 10+A1 is checked twice: a real-table overflow and an I2 overflow
	# both fail named and keep the state.
	var beyond: Dictionary = _state(kernel, 2)
	var beyond_before: Dictionary = beyond.duplicate(true)
	var wide: Dictionary = _consume(commands, beyond, 0, 65)
	check(wide.get("diagnostic", {}).get("code") == "role_backing" and str(wide.error).contains("75-field"),
		"field 75 is beyond the real table: " + str(wide.get("error", "")))
	var wraps: Dictionary = _consume(commands, beyond, 0, 32758)
	check(wraps.get("diagnostic", {}).get("code") == "checked_i2",
		"10+32758 leaves I2 range: " + str(wraps.get("error", "")))
	check(beyond.inventory_bytes == beyond_before.inventory_bytes,
		"the refused field lookups preserve the state")

	# A0 is a role index: 6 and -1 are outside the 6-role table.
	var bad_role: Dictionary = _state(kernel, 2)
	check(_consume(commands, bad_role, 6, 0).has("error")
		and _consume(commands, bad_role, 0xFFFF, 0).has("error"),
		"roles 6 and -1 are refused")

	# The add path has no 99 cap: 99 plus one returned copy is 100.
	var uncapped: Dictionary = _state(kernel, 2)
	_put(uncapped.inventory_bytes, 1, 44, 99)
	uncapped.equipment.role_words[11 * 6] = 44
	var hundred: Dictionary = _consume(commands, uncapped, 0, 1)
	check(not hundred.has("error") and uncapped.inventory_bytes.decode_s16(1 * 6 + 2) == 100,
		"the returned copy lifts 99 to 100 without the compress cap: " + str(hundred.get("error", "")))

	# A full inventory with no matching slot leaves the add ineffective and the
	# original case still clears the field.
	var full: Dictionary = _state(kernel, 2)
	for slot in range(256): _put(full.inventory_bytes, slot, 1000 + slot, 1)
	full.equipment.role_words[12 * 6 + 2] = 9999
	var stuffed: Dictionary = _consume(commands, full, 2, 0)
	check(not stuffed.has("error") and stuffed.effects[0].returned[0].mode == "no_space"
		and full.equipment.role_words[12 * 6 + 2] == 0
		and full.inventory_bytes.decode_s16(0 * 6) == 1000,
		"a full inventory keeps the add silent and the field is cleared anyway: "
			+ str(stuffed.get("error", "")))

	# Duplicate inventory records merge into the first living match only.
	var duplicated: Dictionary = _state(kernel, 2)
	_put(duplicated.inventory_bytes, 4, 30, 2); _put(duplicated.inventory_bytes, 9, 30, 6)
	duplicated.equipment.role_words[11 * 6 + 5] = 30
	var merged: Dictionary = _consume(commands, duplicated, 5, 1)
	check(not merged.has("error") and duplicated.inventory_bytes.decode_s16(4 * 6 + 2) == 3
		and duplicated.inventory_bytes.decode_s16(9 * 6 + 2) == 6,
		"the returned copy merges into slot 4 and leaves slot 9 alone")

	# A second consecutive return overflowing I2 publishes no candidate at all:
	# the earlier field's add and clear vanish with it.
	var overflow: Dictionary = _state(kernel, 2)
	_put(overflow.inventory_bytes, 3, 30, 32766)
	overflow.equipment.role_words[11 * 6 + 1] = 30
	overflow.equipment.role_words[12 * 6 + 1] = 30
	var over_before: Dictionary = overflow.duplicate(true)
	var boom: Dictionary = _consume(commands, overflow, 1, 0)
	check(boom.has("error") and str(boom.error).contains("I2"),
		"the second consecutive return overflows: " + str(boom.get("error", "")))
	check(overflow.inventory_bytes == over_before.inventory_bytes
		and overflow.equipment.role_words[11 * 6 + 1] == 30,
		"the failed sweep applies nothing")

	# The role is absolute: a copy on role 4 outside the projection still
	# returns, unchanged by any projection reorder.
	var outside: Dictionary = _state(kernel, 2)
	_put(outside.inventory_bytes, 6, 21, 1)
	outside.equipment.role_words[13 * 6 + 4] = 21
	var lone: Dictionary = _consume(commands, outside, 4, 3)
	check(not lone.has("error") and lone.effects[0].role == 4
		and outside.equipment.role_words[13 * 6 + 4] == 0
		and outside.inventory_bytes.decode_s16(6 * 6 + 2) == 2,
		"role 4 outside the projection returns through its absolute index: " + str(lone.get("error", "")))
	outside.equipment.party_roles = [3, 1, 0]
	var reordered: Dictionary = _consume(commands, outside, 4, 3)
	check(not reordered.has("error"),
		"the projection reorder does not affect the absolute role lookup")

	# 0020 -> 0023 -> kernel rebuild: the return lands on the post-removal
	# inventory and the equipment state stays rebuildable.
	var chained: Dictionary = _state(kernel, 1)
	chained.equipment = kernel.initial_state([0, 1])
	_put(chained.inventory_bytes, 5, 7, 2)
	chained.equipment.role_words[11 * 6 + 1] = 7
	var removal: Dictionary = commands.consume(chained,
		{"words": [0x0020, 7, 5, 0], "entry": 1, "event_id": 0})
	check(not removal.has("error") and removal.effects[0].unequipped == 1,
		"the 0020 removal drains the record and unequips the copy: " + str(removal.get("error", "")))
	chained.globals.trigger_success_word = -1
	# The member re-equips a fresh copy after the removal, then returns it.
	chained.equipment.role_words[11 * 6 + 1] = 7
	var give_back: Dictionary = _consume(commands, chained, 1, 1)
	check(not give_back.has("error") and chained.equipment.role_words[11 * 6 + 1] == 0
		and chained.inventory_bytes.decode_s16(0 * 6) == 7
		and chained.globals.trigger_success_word == -1,
		"the 0023 return recreates the record and keeps the success word: " + str(give_back.get("error", "")))
	check(kernel.validate_state(chained.equipment) == "",
		"the modified equipment state keeps the kernel shape: " + kernel.validate_state(chained.equipment))
	var rebuilt: Dictionary = kernel.rebuild_party_equipment(chained.equipment)
	check(not rebuilt.has("error") and rebuilt.state.role_words[11 * 6 + 1] == 0,
		"the existing rebuild keeps the post-return equipment results")

	var output: Dictionary = {"suite": "test_pal98_unequip_item", "checks": results,
		"passed": results.size() - failed, "failed": failed}
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n"); file.close()
	print("PASS %d/%d" % [results.size() - failed, results.size()])
	quit(1 if failed > 0 else 0)
