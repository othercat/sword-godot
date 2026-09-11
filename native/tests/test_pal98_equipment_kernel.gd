# SPDX-License-Identifier: MIT
extends SceneTree
const Kernel = preload("res://src/native_pal98_equipment_kernel.gd")
const Reader = preload("res://src/native_json.gd")
var checks: Array = []
var failed: int = 0
var output: String
var real_results: Array = []

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
	_test_tables(); _test_execution(); _test_stats(); _test_bounds()
	if args.size() == 2: _test_real(args[1])
	var report: Dictionary = {"checks": checks, "passed": checks.size() - failed, "failed": failed,
		"real_entries": real_results, "kernel_only": true, "ordinary_native_package": false,
		"complete_party_initializer": false, "original_playthrough": false, "device_acceptance": false}
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
		_unchanged_failure(redirected, redirected.initial_state(), 0, 11, "party_battle_field_unimplemented", 2)
	var negative = _core([[0x1a, 4, 1, 65535]])
	_unchanged_failure(negative, negative.initial_state(), 0, 11, "negative_role_selector_unimplemented", 1)
	var unknown = _core([[0x17, 11, 19, 3], [0x2d, 8, 32760, 0], [0, 0, 0, 0]])
	result = _unchanged_failure(unknown, unknown.initial_state(), 0, 11, "unsupported_opcode", 2)
	check(result.diagnostic.words == [0x2d, 8, 32760, 0] and result.diagnostic.source.source_id == unknown.source_receipt().source_id, "unimplemented status action identifies raw operands and exact source")
	var null_source = _core([[0xffff, 0, 0, 0]])
	state = null_source.initial_state(); state.equip_entries[1] = 0
	result = null_source.run_equipped_entry(state, 0, 11)
	check(result.trace.is_empty() and result.state == state, "zero trigger entry returns without fetching a record")
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

func _test_real(path: String) -> void:
	var reader = Reader.new(); var value = reader.decode(FileAccess.get_file_as_bytes(path))
	check(value is Dictionary and reader.error.is_empty(), "private source fixture is bounded strict JSON")
	if not value is Dictionary: return
	check(value.get("kind") == "private-pal98-equipment-kernel-fixture-v2", "private binary fixture format is explicit")
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
		var state: Dictionary = core.initial_state(); var initial: Dictionary = state.duplicate(true)
		var entries: Array = []; var problem: Dictionary = {}
		var cleared: Dictionary = core.clear_original_modifier_prefix(state); state = cleared.state
		for slot in range(11, 17):
			var result: Dictionary = core.run_equipped_entry(state, role, slot)
			if result.has("error"): problem = result.diagnostic; break
			state = result.state; entries.append(result)
		var expected: Dictionary = value.roles[role]
		if expected.has("failure_pc"):
			check(problem.get("pc") == expected.failure_pc and problem.get("code") == expected.failure_code, "source side effect is diagnosed without silent omission: role " + str(role))
			real_results.append({"role": role, "completed": false, "diagnostic": problem})
			continue
		check(problem.is_empty() and entries.size() == 6, "six equipment fields execute: source role " + str(role))
		if not problem.is_empty(): continue
		var actual: Array = []
		for field in range(17, 31):
			var stat: Dictionary = core.effective_stat(state, role, field)
			check(not stat.has("error"), "source getter within I2 bounds: role %d field %d" % [role, field])
			actual.append(stat.get("value"))
		check(actual == expected.effective_fields_17_30, "all 14 source-backed derived words match independent expectation: role " + str(role))
		check(state.role_words == expected.role_words, "base assignments match source semantics without baking in modifiers: role " + str(role))
		check(state.equip_entries == initial.equip_entries, "0000 retains every shared object entry: source role " + str(role))
		check(core.initial_state() == initial, "source words and initial state stay immutable: role " + str(role))
		var traces: Array = []
		for entry in entries: traces.append({"object_id": entry.object_id, "entry": entry.entry, "return_entry": entry.return_entry, "trace": entry.trace})
		real_results.append({"role": role, "completed": true, "effective_fields_17_30": actual, "entries": traces,
			"state": state, "source": receipt})
