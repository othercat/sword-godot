# SPDX-License-Identifier: MIT
extends SceneTree
const Kernel = preload("res://src/native_pal98_equipment_kernel.gd")
const Reader = preload("res://src/native_json.gd")
const Schema = preload("res://src/native_schema.gd")
var checks: Array = []
var failed: int = 0
var output: String
var real_results: Array = []
var inventory_probe: Dictionary = {}

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _bytes(words: Array) -> PackedByteArray:
	var bytes: PackedByteArray = []; bytes.resize(words.size() * 2)
	for index in range(words.size()): bytes.encode_u16(index * 2, int(words[index]) & 65535)
	return bytes

func _tables(rows: Array = []) -> Array:
	var roles: Array = []; roles.resize(450); roles.fill(0); roles[11 * 6] = 1
	var objects: Array = []; objects.resize(3 * 7); objects.fill(0); objects[7 + 3] = 1; objects[7 + 4] = 2
	var words: Array = [0, 0, 0, 0]
	for row in rows: words.append_array(row)
	return [_bytes(roles), _bytes(objects), _bytes(words)]

func _core(rows: Array = []):
	var core = Kernel.new(); var tables: Array = _tables(rows)
	check(core.read_tables(tables[0], tables[1], tables[2]), "synthetic explicit source tables admitted")
	return core

func _unchanged_failure(core, state: Dictionary, role: int, slot: int, code: String, pc: int = -1, budget: int = 1024) -> Dictionary:
	var before: Dictionary = state.duplicate(true)
	var result: Dictionary = core.run_equipped_entry(state, role, slot, budget)
	check(result.has("error") and not result.has("state") and result.get("diagnostic", {}).get("code") == code,
		"explicit failure without partial candidate: " + code)
	check(state == before, "failed call leaves input state unchanged: " + code)
	if pc >= 0: check(result.get("diagnostic", {}).get("pc") == pc, "failure has exact source PC: " + code)
	return result

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() < 1 or args.size() > 2: push_error("Provide fresh output directory and optional private source fixture"); quit(2); return
	output = args[0]
	if FileAccess.file_exists(output.path_join("results.json")): push_error("Use a fresh evidence directory"); quit(2); return
	if DirAccess.make_dir_recursive_absolute(output) != OK: quit(2); return
	_test_tables(); _test_execution(); _test_stats(); _test_bounds(); _test_party_context(); _test_inventory_preparation()
	if args.size() == 2: _test_real(args[1])
	var report: Dictionary = {"checks": checks, "passed": checks.size() - failed, "failed": failed,
		"real_entries": real_results, "kernel_only": true, "ordinary_native_package": false,
		"complete_party_initializer": false, "original_playthrough": false, "device_acceptance": false,
		"inventory_probe": inventory_probe}
	var file = FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ", true)); file.close()
	print("PAL98 equipment kernel: %d passed, %d failed; %s" % [checks.size() - failed, failed, output])
	quit(0 if failed == 0 else 1)

func _test_tables() -> void:
	var core = Kernel.new()
	check(core.initial_state().is_empty(), "unread source cannot create a state")
	var tables: Array = _tables([[0, 0, 0, 0]])
	check(core.read_tables(tables[0], tables[1], tables[2]), "exact disk formats admitted")
	var receipt: Dictionary = core.source_receipt(); var state: Dictionary = core.initial_state()
	check(receipt.data3_sha256.length() == 64 and receipt.source_id.length() == 64, "all source tables bind a deterministic fingerprint")
	check(state.role_words.size() == 450 and state.modifiers.size() == 588 and state.equip_entries[1] == 1, "unknown fields retained and equip pointer reads object WORD3")
	receipt.source_id = "changed"
	check(core.source_receipt().source_id != receipt.source_id, "receipt reads cannot mutate source identity")
	tables[0].encode_u16(11 * 6 * 2, 2)
	check(core.initial_state().role_words[11 * 6] == 1, "caller byte mutation cannot change parsed roles")
	var other = Kernel.new(); check(other.read_tables(tables[0], tables[1], tables[2]), "different source reads independently")
	check(not other.validate_state(state).is_empty(), "state from another source is rejected")
	var valid: Array = _tables([[0, 0, 0, 0]])
	for bad in [PackedByteArray(), PackedByteArray([0, 0]), PackedByteArray([0]).duplicate()]:
		check(not core.read_tables(bad, valid[1], valid[2]), "bad DATA3 size rejected")
		check(core.initial_state() == state, "failed source replacement preserves previous tables")
	for index in [1, 2]:
		for bad in [PackedByteArray(), PackedByteArray([0]), PackedByteArray([0, 0])]:
			var inputs: Array = valid.duplicate(); inputs[index] = bad
			check(not core.read_tables(inputs[0], inputs[1], inputs[2]), "unaligned or empty object/script table rejected")
	var huge: PackedByteArray = []; huge.resize(65537 * 14)
	check(not core.read_tables(valid[0], huge, valid[2]), "object-count budget enforced")
	huge.resize(65537 * 8)
	check(not core.read_tables(valid[0], valid[1], huge), "instruction-count budget enforced")

func _inventory_bytes() -> PackedByteArray:
	# Deliberately noncanonical inventory, not a claimed original new-game bag:
	# IDs may be zero/unresolved, quantities and use counts retain signed bits.
	var words: Array = []
	for slot in range(256): words.append_array([slot * 257, (0x8000 + slot) & 65535, (0xff00 + slot) & 65535])
	return _bytes(words)

func _test_inventory_preparation() -> void:
	var core = _core([[0x17,11,17,5], [0,0,0,0]])
	var state: Dictionary = core.initial_state(); state.modifiers.fill(9)
	var before: Dictionary = state.duplicate(true)
	var inventory: PackedByteArray = _inventory_bytes(); var original: PackedByteArray = inventory.duplicate()
	var result: Dictionary = core.prepare_party_equipment(state, inventory)
	check(result.has("state") and result.has("inventory_bytes"), "inventory clear and source equipment produce one candidate")
	if not result.has("state"): return
	var preserved: bool = true; var cleared: bool = true
	for slot in range(256):
		preserved = preserved and result.inventory_bytes.slice(slot * 6, slot * 6 + 4) == original.slice(slot * 6, slot * 6 + 4)
		cleared = cleared and result.inventory_bytes.decode_u16(slot * 6 + 4) == 0
	check(preserved and cleared, "all usage words clear while every ID/quantity bit remains")
	check(result.inventory_bytes.decode_u16(0) == 0 and result.inventory_bytes.decode_u16(2) == 0x8000 and result.inventory_bytes.decode_u16(255 * 6) == 0xffff, "empty first slot and signed last-slot patterns do not stop inventory preparation")
	check(inventory == original and state == before, "successful preparation does not mutate either caller input")
	check(result.state == core.rebuild_party_equipment(state).state, "inventory preparation preserves existing equipment result and role5 modifier tail")
	inventory_probe = {"kind": "synthetic-256-slot-inventory", "before_hex": original.hex_encode(), "after_hex": result.inventory_bytes.hex_encode()}
	result.inventory_bytes[0] = 42
	check(inventory == original, "returned inventory bytes are detached")
	for size in [0,6,1535,1537]:
		var bad = PackedByteArray(); bad.resize(size)
		var failure: Dictionary = core.prepare_party_equipment(state, bad)
		check(failure.diagnostic.code == "invalid_inventory_layout" and not failure.has("state") and not failure.has("inventory_bytes"), "inventory layout is explicit: " + str(size))
	var wrong: Dictionary = state.duplicate(true); wrong.source_id = "wrong"
	var invalid: Dictionary = core.prepare_party_equipment(wrong, inventory)
	check(invalid.diagnostic.code == "invalid_state" and not invalid.has("inventory_bytes") and inventory == original, "wrong source state does not publish inventory clear")
	var tables: Array = _tables([[0x17,11,17,5], [0,0,0,0], [0xfe,0,0,0], [0,0,0,0]])
	tables[0].encode_u16((11 * 6 + 1) * 2, 2); tables[1].encode_u16((2 * 7 + 3) * 2, 3)
	var failing = Kernel.new(); check(failing.read_tables(tables[0], tables[1], tables[2]), "later-member failure fixture parses")
	var party: Dictionary = failing.initial_state([0,1]); var party_before: Dictionary = party.duplicate(true)
	var failure: Dictionary = failing.prepare_party_equipment(party, inventory)
	check(failure.diagnostic.code == "unsupported_opcode" and failure.diagnostic.pc == 3 and failure.diagnostic.party_slot == 1 and failure.diagnostic.preparation_phase == "equipment", "late equipment failure retains original PC/member diagnostic")
	check(not failure.has("state") and not failure.has("inventory_bytes") and party == party_before and inventory == original, "late failure publishes neither partial inventory nor earlier member changes")

func _test_execution() -> void:
	var core = _core([[0x18, 11, 1, 0], [0x17, 11, 19, 9], [0x17, 11, 19, 0xfffc], [0, 0, 0, 0]])
	var state: Dictionary = core.initial_state(); state.modifiers.fill(7)
	var before: Dictionary = state.duplicate(true); var result: Dictionary = core.run_equipped_entry(state, 0, 11)
	check(not result.has("error") and state == before, "successful call returns a candidate without mutating its input")
	if result.has("error"): return
	check(result.return_entry == 1 and result.state.equip_entries == before.equip_entries, "0000 writes original U2 entry back to its shared object field")
	check(result.trace.size() == 4 and result.trace[0].pc == 1 and result.trace[3].pc == 4, "trace binds each exact executed source instruction")
	check(result.state.modifiers.slice(0, 14) == [0, 0, -4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "same-item 0018 clears all 14 fields and repeated 0017 replaces instead of adding")
	check(result.state.modifiers.slice(14) == before.modifiers.slice(14), "0018 does not clear other slots or roles")
	check(result.state.role_words == before.role_words and result.state.previous_item == 1, "effect calculation preserves base words and records old item")
	check(result.trace[2].words[3] == 65532 and result.trace[2].after == -4, "raw negative WORD and signed effect both retained")
	var swapped = _core([[0x18, 11, 2, 0], [0, 0, 0, 0]])
	result = swapped.run_equipped_entry(swapped.initial_state(), 0, 11)
	check(not result.has("error") and result.state.role_words[11 * 6] == 2 and result.state.previous_item == 1, "0018 writes another item without inventing an inventory transfer")
	var assigned = _core([[0x1a, 4, 1, 0], [0x1a, 65, 351, 2], [0x1a, 1, 193, 2], [0, 0, 0, 0]])
	result = assigned.run_equipped_entry(assigned.initial_state(), 0, 11)
	check(not result.has("error") and result.state.role_words[4 * 6] == 1, "001A current ordinary role field is a base assignment")
	check(result.state.role_words[65 * 6 + 1] == 351 and result.state.role_words[1 * 6 + 1] == 193, "001A explicit role selection writes base field1/65 rather than current party temporaries")
	check(result.state.modifiers == assigned.initial_state().modifiers, "001A does not turn base assignments into equipment modifiers")
	for field in [1, 65]:
		var redirected = _core([[0x18, 11, 1, 0], [0x1a, field, 351, 0], [0, 0, 0, 0]])
		var projected: Dictionary = redirected.run_equipped_entry(redirected.initial_state(), 0, 11)
		check(not projected.has("error") and projected.state.role_words[field * 6] == 0, "current 001A field1/65 does not overwrite source base")
		check(projected.state.party_fields[0]["battle_sprite_word" if field == 1 else "cooperative_magic_word"] == 351, "current 001A writes the correct party projection")
	var negative = _core([[0x1a, 4, 1, 65535]])
	_unchanged_failure(negative, negative.initial_state(), 0, 11, "negative_role_selector_unimplemented", 1)
	var unknown = _core([[0x17, 11, 19, 3], [0xfe, 8, 32760, 0], [0, 0, 0, 0]])
	result = _unchanged_failure(unknown, unknown.initial_state(), 0, 11, "unsupported_opcode", 2)
	check(result.diagnostic.words == [0xfe, 8, 32760, 0] and result.diagnostic.source.source_id == unknown.source_receipt().source_id, "unimplemented action identifies raw operands and exact source")
	var null_source = _core([[0xffff, 0, 0, 0]])
	state = null_source.initial_state(); state.equip_entries[1] = 0
	result = null_source.run_equipped_entry(state, 0, 11)
	var null_expected: Dictionary = state.duplicate(true); null_expected.trigger_success_word = -1
	check(result.trace.is_empty() and result.state == null_expected, "zero trigger entry keeps caller success initialization but performs no fetch")
	for word in [0, 32768, 65535]:
		state = null_source.initial_state(); state.role_words[11 * 6] = word
		result = null_source.run_equipped_entry(state, 0, 11)
		check(result.get("skipped_nonpositive_item", false) and result.state == state, "initializer skips nonpositive signed item IDs without discarding raw word")
	state = core.initial_state(); state.modifiers.fill(9)
	result = core.clear_original_modifier_prefix(state)
	check(result.state.modifiers.slice(0, 490).all(func(v): return v == 0) and result.state.modifiers.slice(490).all(func(v): return v == 9), "original 490-word clear preserves role5's 98-word tail")
	check(state.modifiers.all(func(v): return v == 9), "prefix clear is also an isolated candidate")

func _test_stats() -> void:
	var core = _core([[0, 0, 0, 0]]); var state: Dictionary = core.initial_state()
	state.role_words[19 * 6] = 1000
	for slot in range(7): state.modifiers[slot * 14 + 2] = slot + 1
	check(core.effective_stat(state, 0, 19).value == 1028, "getter includes slot17 and has no 999 upper cap")
	state = core.initial_state(); state.role_words[22 * 6] = 65535; state.modifiers[22 - 17] = -4
	check(core.effective_stat(state, 0, 22).value == -5, "negative base resistance and effects remain signed without zero clamp")
	state.role_words[22 * 6] = 250; state.modifiers[22 - 17] = 0
	check(core.effective_stat(state, 0, 22).value == 250, "resistance is not clamped to 100")
	for pair in [[32760, 10, -10, "upper"], [32768, -1, 1, "lower"]]:
		state = core.initial_state(); state.role_words[17 * 6] = pair[0]
		state.modifiers[0] = pair[1]; state.modifiers[14] = pair[2]
		var before: Dictionary = state.duplicate(true); var result: Dictionary = core.effective_stat(state, 0, 17)
		check(result.get("diagnostic", {}).get("code") == "i2_overflow" and result.diagnostic.slot == 11, "transient checked I2 overflow cannot be cancelled later: " + pair[3])
		check(state == before, "getter failure leaves input unchanged: " + pair[3])
	for pair in [[32767, 0, 32767], [32768, 0, -32768], [32768, 32767, -1]]:
		state = core.initial_state(); state.role_words[17 * 6] = pair[0]; state.modifiers[0] = pair[1]
		check(core.effective_stat(state, 0, 17).value == pair[2], "signed I2 endpoint arithmetic")
	check(core.effective_stat(state, 6, 17).has("error") and core.effective_stat(state, 0, 7).has("error"), "unknown role and non-modifier HP field are not silently reinterpreted")

func _test_bounds() -> void:
	var core = _core([[0x18, 11, 1, 0], [0, 0, 0, 0]])
	for data in [[-1, 11, 1024, "invalid_context"], [6, 11, 1024, "invalid_context"], [0, 17, 1024, "invalid_context"], [0, 11, 0, "invalid_budget"], [0, 11, 1025, "invalid_budget"], [0, 11, 1, "step_budget"]]:
		_unchanged_failure(core, core.initial_state(), data[0], data[1], data[3], -1, data[2])
	var state: Dictionary = core.initial_state(); state.role_words[11 * 6] = 100
	_unchanged_failure(core, state, 0, 11, "invalid_object")
	state = core.initial_state(); state.equip_entries[1] = 65535
	_unchanged_failure(core, state, 0, 11, "invalid_pc", 65535)
	var tables: Array = _tables([])
	tables[1].encode_u16((7 + 3) * 2, 65535)
	tables[2].resize(65536 * 8)
	tables[2].encode_u16(0, 65535) # Record zero must not be fetched after wrap.
	for column in range(4): tables[2].encode_u16(65535 * 8 + column * 2, [0x17, 11, 19, 1][column])
	var wrapped = Kernel.new()
	check(wrapped.read_tables(tables[0], tables[1], tables[2]), "full U2 instruction address space admitted")
	state = wrapped.initial_state(); var before_wrap: Dictionary = state.duplicate(true)
	var wrap_result: Dictionary = wrapped.run_equipped_entry(state, 0, 11, 1)
	check(not wrap_result.has("error") and wrap_result.return_entry == 0 and wrap_result.state.equip_entries[1] == 0, "FFFF increment wraps and writes null entry back without fetching record zero")
	check(wrap_result.state.modifiers[2] == 1 and wrap_result.trace.size() == 1 and wrap_result.trace[0].pc == 65535, "last U2 instruction commits once even at exact step budget")
	check(state == before_wrap, "U2 wrap still returns an isolated candidate")
	for row in [[0x17, 10, 19, 1], [0x17, 18, 19, 1], [0x17, 11, 16, 1], [0x17, 11, 31, 1]]:
		var bad = _core([row]); _unchanged_failure(bad, bad.initial_state(), 0, 11, "invalid_effect_address", 1)
	for row in [[0x18, 10, 1, 0], [0x18, 17, 1, 0]]:
		var bad = _core([row]); _unchanged_failure(bad, bad.initial_state(), 0, 11, "invalid_equipment_address", 1)
	for row in [[0x1a, 75, 1, 0], [0x1a, 4, 1, 7]]:
		var bad = _core([row]); _unchanged_failure(bad, bad.initial_state(), 0, 11, "invalid_role_address", 1)
	var no_return = _core([[0x17, 11, 19, 1]])
	_unchanged_failure(no_return, no_return.initial_state(), 0, 11, "invalid_pc", 2)
	for defect in ["foreign", "extra", "null", "short", "negative_word", "effect_overflow", "float", "bool", "bad_previous"]:
		state = core.initial_state()
		match defect:
			"foreign": state.source_id = "different"
			"extra": state.extra = 1
			"null": state.role_words = null
			"short": state.modifiers.pop_back()
			"negative_word": state.role_words[0] = -1
			"effect_overflow": state.modifiers[0] = 32768
			"float": state.equip_entries[0] = 1.0
			"bool": state.role_words[0] = false
			"bad_previous": state.previous_item = 65536
		_unchanged_failure(core, state, 0, 11, "invalid_state")

func _test_party_context() -> void:
	var core = _core([[0x18, 11, 1, 0], [0x1a, 4, 1, 0], [0x1a, 1, 6, 0], [0x1a, 65, 351, 0], [0x2d, 8, 32760, 65535], [0, 0, 0, 0]])
	var state: Dictionary = core.initial_state([5, 1])
	state.role_words[11 * 6 + 5] = 1; state.role_words[1 * 6 + 5] = 123; state.role_words[65 * 6 + 5] = 456
	state.party_statuses[1][8] = 100
	var before: Dictionary = state.duplicate(true); var result: Dictionary = core.run_equipped_entry(state, 5, 11)
	check(not result.has("error") and state == before, "source role5 resolves through party slot0 without mutating input")
	check(result.state.party_statuses[0][8] == 32760 and result.state.party_statuses[1][8] == 100, "002D owns party-slot status rather than source-role status")
	check(result.state.party_fields[0] == {"battle_sprite_word": 6, "cooperative_magic_word": 351}, "current field1/65 updates two known offsets without guessing a full record stride")
	check(result.state.role_words[1 * 6 + 5] == 123 and result.state.role_words[65 * 6 + 5] == 456 and result.state.role_words[4 * 6 + 5] == 1, "ordinary role field and party temporaries keep distinct owners")
	check(result.state.trigger_success_word == -1 and result.state.role_words[9 * 6 + 5] == 0, "status8 ignores HP and Arg2 without inventing a failure or render")
	result = core.rebuild_party_equipment(state)
	check(not result.has("error") and result.entries.size() == 12 and state == before, "two-member rebuild is one isolated candidate")
	check(result.state.party_statuses[0][8] == 32760 and result.state.party_statuses[1][8] == 0, "rebuild clears each slot's status8 before its own equipment")
	for vector in [[0, 5, 10, 5], [3, 0, 10, 10], [3, -5, -1, -1], [2, 0, -1, 0], [0, -2, -3, -2],
		[5, 5, 10, 10], [8, 100, 32760, 32760], [8, 32767, 32760, 32767], [8, 32760, 32760, 32760],
		[1, 1, 32760, 1], [7, -32768, 32767, 32767], [6, 0, -32768, 0], [8, 32760, 32767, 32767], [5, 999, 1000, 1000]]:
		var action = _core([[0x2d, vector[0], vector[2] & 65535, 32767], [0, 0, 0, 0]])
		var input: Dictionary = action.initial_state(); input.party_statuses[0][vector[0]] = vector[1]
		var actual: Dictionary = action.run_equipped_entry(input, 0, 11)
		check(not actual.has("error") and actual.state.party_statuses[0][vector[0]] == vector[3], "002D signed qualification/replacement vector " + str(vector))
		check(actual.state.trigger_success_word == -1, "unchanged duration does not clear trigger success")
	var pose = _core([[0x17, 11, 19, 1], [0x2d, 4, 100, 0], [0x2d, 8, 10, 0], [0, 0, 0, 0]])
	for hp in [0, 65535]:
		state = pose.initial_state(); state.role_words[9 * 6] = hp
		_unchanged_failure(pose, state, 0, 11, "status4_render_unimplemented", 2)
	state = pose.initial_state(); state.role_words[9 * 6] = 1; state.party_statuses[0][4] = 3
	result = pose.run_equipped_entry(state, 0, 11)
	check(not result.has("error") and result.state.party_statuses[0][4] == 3 and result.state.trigger_success_word == 0, "status4 on living role retains duration and clears success; later status8 does not set it back")
	check(result.state.party_statuses[0][8] == 10, "later non4 status action still executes after status4 qualification failure")
	for status in [65535, 9]:
		var bad = _core([[0x2d, status, 1, 0]])
		_unchanged_failure(bad, bad.initial_state(), 0, 11, "invalid_status_address", 1)
	var tables: Array = _tables([[0x1a, 1, 99, 2], [0, 0, 0, 0], [0x1a, 65, 351, 0], [0, 0, 0, 0]])
	tables[0].encode_u16((11 * 6 + 1) * 2, 2); tables[1].encode_u16((2 * 7 + 3) * 2, 3)
	var ordered = Kernel.new(); check(ordered.read_tables(tables[0], tables[1], tables[2]), "ordered two-member source admitted")
	state = ordered.initial_state([0, 1]); state.role_words[4 * 6] = 7; state.role_words[4 * 6 + 1] = 9
	state.party_statuses[0][2] = 4; before = state.duplicate(true)
	result = ordered.rebuild_party_equipment(state)
	check(not result.has("error") and result.state.party_fields[1].battle_sprite_word == 99, "earlier equipment base assignment precedes the later member's copy")
	check(result.state.role_words[4 * 6] == 0 and result.state.role_words[4 * 6 + 1] == 0 and result.state.party_statuses[0][2] == 4, "rebuild clears only the specified role flag and status8")
	check(result.state.party_fields[1].cooperative_magic_word == 351 and state == before, "later equipment temporary replaces copied field inside one transaction")
	tables[2].encode_u16(3 * 8, 0xfe)
	var failing = Kernel.new(); check(failing.read_tables(tables[0], tables[1], tables[2]), "late-failure source admitted")
	state = failing.initial_state([0, 1]); before = state.duplicate(true); result = failing.rebuild_party_equipment(state)
	check(result.has("error") and not result.has("state") and state == before, "later member failure rolls back all earlier member preparation and equipment")
	check(result.diagnostic.party_slot == 1 and result.diagnostic.role == 1 and result.diagnostic.pc == 3, "late failure identifies member and actual source PC")
	check(core.initial_state([0, 1, 2, 3]).is_empty() and core.initial_state([0, 0]).is_empty(), "source party capacity and duplicate role inputs are explicit")
	_unchanged_failure(core, core.initial_state([1]), 0, 11, "invalid_context")
	for defect in ["member", "duplicate", "missing_field", "extra_field", "bad_word", "status_size", "status_range", "status_bool", "success"]:
		state = core.initial_state([0, 1])
		match defect:
			"member": state.party_roles[0] = 6
			"duplicate": state.party_roles[1] = 0
			"missing_field": state.party_fields.pop_back()
			"extra_field": state.party_fields[0].frame = 1
			"bad_word": state.party_fields[0].battle_sprite_word = -1
			"status_size": state.party_statuses[0].pop_back()
			"status_range": state.party_statuses[0][0] = 32768
			"status_bool": state.party_statuses[0][0] = false
			"success": state.trigger_success_word = 32768
		_unchanged_failure(core, state, 0, 11, "invalid_state")

func _test_real(path: String) -> void:
	var reader = Reader.new(); var value = reader.decode(FileAccess.get_file_as_bytes(path))
	check(value is Dictionary and reader.error.is_empty(), "private source fixture is bounded strict JSON")
	if not value is Dictionary: return
	check(value.get("kind") == "private-pal98-equipment-kernel-fixture-v3", "private party-context binary fixture format is explicit")
	if value.get("kind") != "private-pal98-equipment-kernel-fixture-v3": return
	var tables: Array = []
	for row in [["data3", 900], ["objects", 65536 * 14], ["scripts", 65536 * 8]]:
		var name: String = value.get(row[0] + "_file", "")
		if name.is_empty() or name != name.get_file() or name.is_absolute_path():
			check(false, "binary fixture requires sibling file names"); return
		var input = FileAccess.open(path.get_base_dir().path_join(name), FileAccess.READ)
		if input == null or input.get_length() > row[1]:
			check(false, "binary fixture is missing or exceeds byte budget"); return
		tables.append(input.get_buffer(input.get_length())); input.close()
	var core = Kernel.new()
	check(core.read_tables(tables[0], tables[1], tables[2]), "actual source tables parse in independent Native kernel")
	if not core.error.is_empty(): return
	var receipt: Dictionary = core.source_receipt()
	for key in ["data3_sha256", "objects_sha256", "scripts_sha256"]:
		check(receipt[key] == value[key], "exact private source chunk bytes: " + key)
	for role in range(6):
		var initial: Dictionary = core.initial_state([role]); var inventory: PackedByteArray = _inventory_bytes()
		var result: Dictionary = core.prepare_party_equipment(initial, inventory)
		var problem: Dictionary = result.get("diagnostic", {})
		var entries: Array = result.get("entries", []); var state: Dictionary = result.get("state", {})
		var expected: Dictionary = value.roles[role]
		if expected.has("failure_pc"):
			check(problem.get("pc") == expected.failure_pc and problem.get("code") == expected.failure_code, "source side effect is diagnosed without silent omission: role " + str(role))
			real_results.append({"role": role, "completed": false, "diagnostic": problem})
			continue
		check(problem.is_empty() and entries.size() == 6, "six equipment fields execute: source role " + str(role))
		if not problem.is_empty(): continue
		check(result.inventory_bytes.hex_encode() == inventory_probe.after_hex and inventory.hex_encode() == inventory_probe.before_hex, "real source equipment combines with explicitly synthetic inventory without mutating input: role " + str(role))
		var actual: Array = []
		for field in range(17, 31):
			var stat: Dictionary = core.effective_stat(state, role, field)
			check(not stat.has("error"), "source getter within I2 bounds: role %d field %d" % [role, field])
			actual.append(stat.get("value"))
		check(actual == expected.effective_fields_17_30, "all 14 source-backed derived words match independent expectation: role " + str(role))
		check(state.role_words == expected.role_words, "base assignments match source semantics without baking in modifiers: role " + str(role))
		check(state.equip_entries == initial.equip_entries, "0000 retains every shared object entry: source role " + str(role))
		for key in ["party_roles", "party_fields", "party_statuses", "trigger_success_word"]:
			check(state[key] == expected[key], "actual source party projection: role %d %s" % [role, key])
		check(core.initial_state([role]) == initial, "source words and initial state stay immutable: role " + str(role))
		var traces: Array = []
		for entry in entries: traces.append({"object_id": entry.object_id, "entry": entry.entry, "return_entry": entry.return_entry, "trace": entry.trace})
		real_results.append({"role": role, "completed": true, "effective_fields_17_30": actual, "entries": traces,
			"state": state, "source": receipt, "inventory_before_sha256": Schema.digest(inventory),
			"inventory_after_sha256": Schema.digest(result.inventory_bytes)})
