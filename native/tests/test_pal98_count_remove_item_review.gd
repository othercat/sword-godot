# SPDX-License-Identifier: MIT
extends "res://tests/test_pal98_enter_script.gd"
## Independent 0020 review vectors, including the original checked-I2 branch
## boundary and real Trigger/EntryHost integration. The synthetic state and
## admitted package are explicit inputs; these are not gameplay assertions.

func _review_state() -> Dictionary:
	var words: Array = []; words.resize(450); words.fill(0)
	return {"globals": {"member_last": 0},
		"equipment": {"role_words": words, "party_roles": [0]}, "inventory_bytes": _zero(1536)}

func _put_item(state: Dictionary, slot: int, item: int, amount: int, in_use: int = 0) -> void:
	state.inventory_bytes.encode_s16(slot * 6, item)
	state.inventory_bytes.encode_s16(slot * 6 + 2, amount)
	state.inventory_bytes.encode_s16(slot * 6 + 4, in_use)

func _item_words(state: Dictionary, slot: int) -> Array:
	return [state.inventory_bytes.decode_s16(slot * 6),
		state.inventory_bytes.decode_s16(slot * 6 + 2), state.inventory_bytes.decode_s16(slot * 6 + 4)]

func _remove(commands, state: Dictionary, item: int, amount: int, target: int) -> Dictionary:
	return commands.consume(state, {"words": [0x0020, item, amount, target], "entry": 1, "event_id": 0})

func _review_vectors(commands) -> void:
	var inventory = Inventory.new()
	var state: Dictionary = _review_state()
	state.globals.member_last = 1; _put_item(state, 0, 7, 1)
	var before: Dictionary = state.duplicate(true)
	var result: Dictionary = _remove(commands, state, 7, 2, 9)
	check(result.has("error") and state == before,
		"an incomplete projection cannot publish a partial shortage jump")
	state = before.duplicate(true); result = _remove(commands, state, 7, 2, 0)
	check(result.has("error") and state == before,
		"an incomplete projection cannot publish an inventory removal")

	state = _review_state(); before = state.duplicate(true)
	result = _remove(commands, state, 7, 1, 0x8000)
	check(result.get("diagnostic", {}).get("code") == "checked_i2" and state == before,
		"shortage A2=-32768 fails the original checked I2 subtraction without state changes")
	state = _review_state(); result = _remove(commands, state, 7, 1, 0xffff)
	check(not result.has("error") and result.get("entry") == 65534,
		"valid A2=-1 maps checked -2 to ByRef U2 65534")
	state = _review_state(); result = _remove(commands, state, 7, 1, 1)
	check(not result.has("error") and result.get("entry") == 0,
		"A2=1 maps to ByRef zero")
	state = _review_state(); _put_item(state, 0, 7, 1)
	result = _remove(commands, state, 7, 1, 0x8000)
	check(not result.has("error") and _item_words(state, 0) == [7, 0, 0],
		"unused A2=-32768 does not fail the sufficient-stock branch")

	state = _review_state(); _put_item(state, 0, 30, 1); _put_item(state, 1, 30, 2, -32768)
	before = state.duplicate(true); result = _remove(commands, state, 30, 2, 0)
	check(result.has("error") and state == before,
		"an overflow after an earlier candidate change preserves all input state")
	state = _review_state(); _put_item(state, 0, 30, 2, 10); _put_item(state, 1, 30, 4, 8)
	result = _remove(commands, state, 30, 5, 0)
	check(not result.has("error") and _item_words(state, 0) == [0, 0, 5]
		and _item_words(state, 1) == [30, 1, 5],
		"duplicate slots decrement in-use by each current remaining value")
	state = _review_state(); state.globals.member_last = 1; state.equipment.party_roles = [3, 1]
	state.equipment.role_words[11 * 6 + 3] = 30
	state.equipment.role_words[16 * 6 + 3] = 30
	state.equipment.role_words[11 * 6 + 1] = 30
	result = _remove(commands, state, 30, 2, 0)
	check(not result.has("error") and state.equipment.role_words[11 * 6 + 3] == 0
		and state.equipment.role_words[16 * 6 + 3] == 0 and state.equipment.role_words[11 * 6 + 1] == 30,
		"unequip order is member first then field for each copy")
	state = _review_state(); _put_item(state, 0, 30, 3, 3)
	state.equipment.role_words[11 * 6] = 30; state.equipment.role_words[12 * 6] = 30
	result = _remove(commands, state, 30, 6, 9)
	check(not result.has("error") and result.get("effects", [{}])[0].get("count") == 5,
		"count ignores in-use and adds equipped copies to amount")
	state = _review_state(); _put_item(state, 0, 30, 2, 7)
	result = _remove(commands, state, 30, 2, 0)
	check(not result.has("error") and _item_words(state, 0) == [30, 0, 5],
		"exact exhaustion retains item identity and remaining usage")
	state = _review_state(); _put_item(state, 0, 7, 1); before = state.duplicate(true)
	result = inventory.remove_inventory_item_and_unequip_shortfall(
		state.inventory_bytes, 7, 2, state.equipment.role_words, [0], 1)
	check(result.has("error") and state == before,
		"the inventory helper independently rejects an incomplete projection")

	state = _review_state(); state.equipment.role_words[66] = 65543
	before = state.duplicate(true); result = _remove(commands, state, 7, 3, 9)
	check(result.has("error") and state == before,
		"an invalid role WORD cannot be converted into a valid equipped item")
	state = _review_state(); state.equipment.role_words[66] = 7
	state.equipment.party_roles = [0, 0]; state.globals.member_last = 1
	before = state.duplicate(true); result = _remove(commands, state, 7, 3, 9)
	check(result.has("error") and state == before,
		"a repeated active role cannot count the same equipped item twice")

func _review_integration() -> void:
	var source = _source([0, 0], [1, 0], [[0x0020, 7, 2, 3], [0x004A, 99, 0, 0], [1, 0, 0, 0]])
	for amount in [1, 2]:
		var owner = _owner(source); var state: Dictionary = _fixture(source)
		_put_item(state, 0, 7, amount)
		var result: Dictionary = owner.start(state, 1, 1)
		check(not result.has("error") and result.has("return_entry")
			and result.state.globals.get("battlefield_word", 0) == (0 if amount == 1 else 99),
			"real Trigger branches to A2 or continues to the marker: amount=" + str(amount))
	var kernel = Equipment.new()
	kernel.read_tables(source.copy_chunk("data", 3), source.copy_chunk("sss", 2), source.copy_chunk("sss", 4))
	var bound_bag: PackedByteArray = _zero(1536)
	bound_bag.encode_s16(0, 7); bound_bag.encode_s16(2, 4)
	var host = EntryHost.new(); host.bind(RefCounted.new(), kernel, bound_bag, [0, 0, 0, 0, 0, 0])
	var current: Dictionary = _fixture(source)
	_put_item(current, 0, 7, 1); current.equipment.role_words[13 * 6 + 1] = 7
	var commands = Commands.new(); commands.load_source(source)
	var removed: Dictionary = _remove(commands, current, 7, 2, 0)
	var rebuilt: Dictionary = host.answer({"kind": "rebuild_party_equipment", "state": current})
	check(not removed.has("error") and rebuilt.get("completed", false)
		and current.inventory_bytes.decode_s16(2) == 0 and bound_bag.decode_s16(2) == 4,
		"real EntryHost rebuild preserves post-0020 inventory rather than its bound bag")
	check(current.equipment.role_words[13 * 6 + 1] == 0,
		"real equipment rebuild keeps the field removed by 0020")

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]) or DirAccess.dir_exists_absolute(args[1]):
		quit(2); return
	var admitted = Package.new()
	if not admitted.load_package(args[0]): push_error(str(admitted.error)); quit(2); return
	var commands = Commands.new()
	if not commands.load_source(admitted.pal98_sources): quit(2); return
	_review_vectors(commands)
	_review_integration()
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	if file == null: quit(2); return
	file.store_string(JSON.stringify({"suite": "test_pal98_count_remove_item_review",
		"passed": checks.size() - failed, "failed": failed, "checks": checks}, "\t") + "\n")
	file.close()
	print("0020 review: ", checks.size() - failed, "/", checks.size())
	quit(0 if failed == 0 else 1)
