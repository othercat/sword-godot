# SPDX-License-Identifier: MIT
extends SceneTree
## 0x0020 closes the count-then-jump-or-remove loop: the count takes the last
## active inventory slot's amount (duplicates never sum) plus the active
## members' equipment fields 11..16, a shortage with nonzero A2 rewrites the
## ByRef entry to A2-1, and otherwise T135 removes the amount, clears exhausted
## records and unequips one field per shortage copy. Every failure keeps the
## prior state and the consumer reads the latest inventory, not a bind-time
## snapshot.
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

func _put(inventory: PackedByteArray, slot: int, item: int, amount: int, in_use: int = 0) -> void:
	inventory.encode_s16(slot * 6, item); inventory.encode_s16(slot * 6 + 2, amount)
	inventory.encode_s16(slot * 6 + 4, in_use)

func _state(kernel, member_last: int) -> Dictionary:
	var globals: Dictionary = {"current_scene": 1, "battle_mode": 0, "member_last": member_last,
		"follower_count": 0, "trigger_success_word": 0}
	var state: Dictionary = {"globals": globals, "equipment": kernel.initial_state([0, 1, 3]),
		"inventory_bytes": _inventory_bytes()}
	return state

func _equip(state: Dictionary, role: int, field: int, item: int) -> void:
	state.equipment.role_words[field * 6 + role] = item

func _consume(commands, state: Dictionary, item: int, amount: int, entry_word: int) -> Dictionary:
	return commands.consume(state, {"words": [0x0020, item, amount, entry_word], "entry": 1, "event_id": 0})

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

	# T173: the last active slot's amount plus equipped copies; slot 5's 4
	# copies are shadowed by slot 9's 3 and must not sum.
	var counted: Dictionary = _state(kernel, 2)
	_put(counted.inventory_bytes, 5, 30, 4); _put(counted.inventory_bytes, 9, 30, 3)
	_equip(counted, 0, 11, 30); _equip(counted, 0, 14, 30)
	var shortage: Dictionary = _consume(commands, counted, 30, 6, 9)
	check(not shortage.has("error") and shortage.entry == 8
		and shortage.effects[0].kind == "inventory_shortage_jump" and shortage.effects[0].count == 5,
		"the count is last-slot 3 plus equipped 2 and A2=9 rewrites the ByRef entry to 8: "
			+ str(shortage.get("error", "")))
	check(counted.inventory_bytes.decode_s16(9 * 6 + 2) == 3
		and counted.equipment.role_words[11 * 6] == 30,
		"the shortage jump removes nothing")

	# Only a zero A1 defaults to one; enough stock consumes from the first
	# matching record and the in-use clamp mirrors the original.
	var defaulted: Dictionary = _state(kernel, 2)
	_put(defaulted.inventory_bytes, 5, 30, 4, 2); _put(defaulted.inventory_bytes, 9, 30, 3)
	var one: Dictionary = _consume(commands, defaulted, 30, 0, 0)
	check(not one.has("error") and one.effects[0].consumed == 1
		and defaulted.inventory_bytes.decode_s16(5 * 6 + 2) == 3
		and defaulted.inventory_bytes.decode_s16(5 * 6 + 4) == 1,
		"a zero A1 removes one and the in-use decrement lands on one without clamping: "
			+ str(one.get("error", "")))
	check(defaulted.inventory_bytes.decode_s16(9 * 6 + 2) == 3,
		"the later duplicate slot is untouched by the first record's removal")

	# A2=0 falls through to removal: the exhausted record clears and each
	# shortage copy clears the first matching field 11..16 over active members.
	var fallen: Dictionary = _state(kernel, 1)
	fallen.equipment = kernel.initial_state([0, 1])
	_put(fallen.inventory_bytes, 2, 7, 2)
	_equip(fallen, 1, 12, 7); _equip(fallen, 1, 13, 7)
	var remove_all: Dictionary = _consume(commands, fallen, 7, 5, 0)
	check(not remove_all.has("error") and remove_all.effects[0].consumed == 2
		and remove_all.effects[0].unequipped == 2 and remove_all.effects[0].shortage_left == 3,
		"the A2=0 shortage clears the record and unequips two of three copies: "
			+ str(remove_all.get("error", "")))
	check(fallen.inventory_bytes.decode_s16(2 * 6) == 0 and fallen.inventory_bytes.decode_s16(2 * 6 + 2) == 0
		and fallen.equipment.role_words[12 * 6 + 1] == 0 and fallen.equipment.role_words[13 * 6 + 1] == 0,
		"the exhausted record and both equipped copies are cleared")

	# Enough stock with an in-use clamp: 2 equipped, remove 3 of 5.
	var clamped: Dictionary = _state(kernel, 1)
	clamped.equipment = kernel.initial_state([0, 1])
	_put(clamped.inventory_bytes, 4, 11, 5, 2)
	var enough: Dictionary = _consume(commands, clamped, 11, 3, 0)
	check(not enough.has("error") and enough.effects[0].consumed == 3
		and clamped.inventory_bytes.decode_s16(4 * 6 + 2) == 2
		and clamped.inventory_bytes.decode_s16(4 * 6 + 4) == 0,
		"the in-use 2-3 decrement clamps to zero and the amount drops to 2: " + str(enough.get("error", "")))

	# Multi-record consumption walks slots in order before unequipping.
	var walked: Dictionary = _state(kernel, 2)
	_put(walked.inventory_bytes, 3, 21, 2); _put(walked.inventory_bytes, 6, 21, 2)
	var drained: Dictionary = _consume(commands, walked, 21, 5, 0)
	check(not drained.has("error") and drained.effects[0].shortage_left == 1
		and walked.inventory_bytes.decode_s16(3 * 6) == 0 and walked.inventory_bytes.decode_s16(6 * 6) == 0,
		"two records drain in slot order and leave one shortage copy: " + str(drained.get("error", "")))

	# The projection follows party_roles identities: a copy equipped on role 3
	# stays countable across a reorder, while a copy on the unprojected role 2
	# never counts.
	var reordered: Dictionary = _state(kernel, 1)
	reordered.equipment = kernel.initial_state([3, 1])
	_equip(reordered, 3, 15, 44); _equip(reordered, 2, 11, 44)
	var before: Dictionary = reordered.duplicate(true)
	var identity: Dictionary = _consume(commands, reordered, 44, 2, 7)
	check(not identity.has("error") and identity.entry == 6 and identity.effects[0].count == 1,
		"the equipped copy on role 3 counts and the unprojected role 2 copy does not: "
			+ str(identity.get("error", "")))
	reordered.equipment.party_roles = [1, 3]
	var after_reorder: Dictionary = _consume(commands, reordered, 44, 2, 7)
	check(not after_reorder.has("error") and after_reorder.effects[0].count == 1,
		"swapping the projection keeps the role 3 copy countable")
	_equip(reordered, 1, 12, 44)
	var both: Dictionary = _consume(commands, reordered, 44, 3, 7)
	check(not both.has("error") and both.effects[0].count == 2,
		"adding a role 1 copy lifts the reordered count to two")
	check(reordered.inventory_bytes == before.inventory_bytes,
		"the shortage jumps applied no inventory writes")

	# Checked I2: a combined count past 32767 fails before any write and an
	# overflowing in-use decrement fails atomically.
	var overflow: Dictionary = _state(kernel, 1)
	overflow.equipment = kernel.initial_state([0, 1])
	_put(overflow.inventory_bytes, 9, 30, 32767); _equip(overflow, 1, 11, 30)
	var over_before: Dictionary = overflow.duplicate(true)
	var over: Dictionary = _consume(commands, overflow, 30, 40000, 0)
	check(over.get("diagnostic", {}).get("code") == "inventory_count" and str(over.error).contains("I2"),
		"the combined count overflow is a named failure: " + str(over.get("error", "")))
	check(overflow.inventory_bytes == over_before.inventory_bytes,
		"the failed count preserves the inventory")
	var in_use_over: Dictionary = _state(kernel, 1)
	in_use_over.equipment = kernel.initial_state([0, 1])
	_put(in_use_over.inventory_bytes, 8, 44, 1, -32768)
	var in_use_before: Dictionary = in_use_over.duplicate(true)
	var in_use: Dictionary = _consume(commands, in_use_over, 44, 1, 0)
	check(in_use.get("diagnostic", {}).get("code") == "inventory_remove"
		and str(in_use.error).contains("in-use"),
		"the in-use decrement overflow is a named failure: " + str(in_use.get("error", "")))
	check(in_use_over.inventory_bytes == in_use_before.inventory_bytes
		and in_use_over.equipment.role_words == in_use_before.equipment.role_words,
		"the failed removal preserves inventory and equipment words")

	# A negative amount keeps the removal path with nothing to consume.
	var negative: Dictionary = _state(kernel, 2)
	_put(negative.inventory_bytes, 5, 30, 4)
	var negative_before: Dictionary = negative.duplicate(true)
	var minus: Dictionary = _consume(commands, negative, 30, 0x8000, 0)
	check(not minus.has("error") and minus.effects[0].consumed == 0
		and negative.inventory_bytes == negative_before.inventory_bytes,
		"a negative A1 consumes nothing and preserves the state")

	# The consumer chains on the latest state: the second command sees the
	# first removal, and the modified equipment state still validates and
	# rebuilds through the existing kernel.
	var chained: Dictionary = _state(kernel, 1)
	chained.equipment = kernel.initial_state([0, 1])
	_put(chained.inventory_bytes, 5, 30, 4)
	_consume(commands, chained, 30, 3, 0)
	var second: Dictionary = _consume(commands, chained, 30, 4, 6)
	check(not second.has("error") and second.entry == 5 and second.effects[0].count == 1,
		"the follow-up command counts the post-removal inventory: " + str(second.get("error", "")))
	_equip(chained, 1, 13, 30)
	var final: Dictionary = _consume(commands, chained, 30, 2, 0)
	check(not final.has("error") and final.effects[0].unequipped == 1
		and chained.equipment.role_words[13 * 6 + 1] == 0,
		"the last shortage copy unequips the field 13 copy: " + str(final.get("error", "")))
	check(kernel.validate_state(chained.equipment) == "",
		"the modified state keeps the kernel equipment shape: " + kernel.validate_state(chained.equipment))
	var rebuilt: Dictionary = kernel.rebuild_party_equipment(chained.equipment)
	check(not rebuilt.has("error") and rebuilt.state.role_words[13 * 6 + 1] == 0,
		"the existing rebuild keeps the post-removal equipment results")

	var output: Dictionary = {"suite": "test_pal98_count_remove_item", "checks": results,
		"passed": results.size() - failed, "failed": failed}
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n"); file.close()
	print("PASS %d/%d" % [results.size() - failed, results.size()])
	quit(1 if failed > 0 else 0)
