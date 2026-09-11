# SPDX-License-Identifier: MIT
extends RefCounted
## Bounded, independently written execution of recovered equipment-entry actions
## entry subset. This is an internal kernel, not Native package/save admission or
## the complete 0075 party rebuild. No source game code is loaded or evaluated.
const ROLES = 6
const ROLE_FIELDS = 75
const FIRST_SLOT = 11
const LAST_SLOT = 17
const FIRST_EFFECT = 17
const LAST_EFFECT = 30
const MODIFIER_COUNT = ROLES * 7 * 14
const MAX_STEPS = 1024
const PROFILE = "pal98.equipment-entry-subset.v1"
var error: String = ""
var _roles: Array = []
var _objects: Array = []
var _scripts: Array = []
var _receipt: Dictionary = {}

static func _sha(bytes: PackedByteArray) -> String:
	var context = HashingContext.new()
	context.start(HashingContext.HASH_SHA256); context.update(bytes)
	return context.finish().hex_encode()

static func _words(bytes: PackedByteArray) -> Array:
	var result: Array = []
	for offset in range(0, bytes.size(), 2): result.append(bytes.decode_u16(offset))
	return result

static func _signed(word: int) -> int:
	return word if word < 32768 else word - 65536

static func _modifier_index(role: int, slot: int, field: int) -> int:
	# Internal logical storage; not a declaration of a native VB array descriptor.
	return (role * 7 + slot - FIRST_SLOT) * 14 + field - FIRST_EFFECT

func read_tables(data3: PackedByteArray, objects: PackedByteArray, scripts: PackedByteArray) -> bool:
	# Parse the explicit Win95/98 disk layout. Names, external profiles and source
	# path selection belong to the importer; no guessing or fallback happens here.
	if data3.size() != ROLES * ROLE_FIELDS * 2:
		error = "DATA3 requires the explicit 900-byte six-role layout"; return false
	if objects.is_empty() or objects.size() % 14 != 0 or objects.size() > 65536 * 14:
		error = "SSS2 requires 1..65536 fourteen-byte object records"; return false
	if scripts.is_empty() or scripts.size() % 8 != 0 or scripts.size() > 65536 * 8:
		error = "SSS4 requires 1..65536 eight-byte instructions"; return false
	var receipt: Dictionary = {"profile": PROFILE, "data3_sha256": _sha(data3),
		"objects_sha256": _sha(objects), "scripts_sha256": _sha(scripts),
		"object_count": int(objects.size() / 14), "instruction_count": int(scripts.size() / 8)}
	receipt.source_id = _sha((PROFILE + "\n" + receipt.data3_sha256 + "\n" + receipt.objects_sha256 + "\n" + receipt.scripts_sha256).to_utf8_buffer())
	_roles = _words(data3); _objects = _words(objects); _scripts = _words(scripts)
	_receipt = receipt; error = ""; return true

func source_receipt() -> Dictionary:
	return _receipt.duplicate(true)

func initial_state() -> Dictionary:
	if _receipt.is_empty(): return {}
	var effects: Array = []; effects.resize(MODIFIER_COUNT); effects.fill(0)
	var entries: Array = []
	for index in range(int(_receipt.object_count)): entries.append(_objects[index * 7 + 3])
	return {"source_id": _receipt.source_id, "role_words": _roles.duplicate(),
		"modifiers": effects, "equip_entries": entries, "previous_item": 0}

func validate_state(state: Dictionary) -> String:
	if _receipt.is_empty(): return "source tables have not been read"
	if state.size() != 5 or state.get("source_id") != _receipt.source_id:
		return "equipment state source or shape mismatch"
	for field in ["role_words", "modifiers", "equip_entries"]:
		if not state.get(field) is Array: return "equipment state requires word arrays"
		var expected: int = ROLES * ROLE_FIELDS if field == "role_words" else MODIFIER_COUNT if field == "modifiers" else int(_receipt.object_count)
		if state[field].size() != expected: return "equipment state array length mismatch: " + field
		var low: int = -32768 if field == "modifiers" else 0
		var high: int = 32767 if field == "modifiers" else 65535
		for word in state[field]:
			if typeof(word) != TYPE_INT or word < low or word > high: return "equipment state word out of range: " + field
	if typeof(state.get("previous_item")) != TYPE_INT or state.previous_item < 0 or state.previous_item > 65535:
		return "previous equipment object is not a WORD"
	return ""

func _failure(code: String, message: String, pc: int = -1, words: Array = [], steps: int = 0) -> Dictionary:
	# A failed call never publishes the partially evaluated candidate.
	return {"error": message, "diagnostic": {"code": code, "source": source_receipt(),
		"pc": pc, "words": words.duplicate(), "steps": steps}}

func clear_original_modifier_prefix(state: Dictionary) -> Dictionary:
	var issue: String = validate_state(state)
	if not issue.is_empty(): return _failure("invalid_state", issue)
	var candidate: Dictionary = state.duplicate(true)
	# The original initializer clears 490 of 588 I2 values. Keep role 5's tail;
	# clearing all six roles here would silently change the recovered behavior.
	for index in range(490): candidate.modifiers[index] = 0
	return {"state": candidate}

func effective_stat(state: Dictionary, role: int, field: int) -> Dictionary:
	var issue: String = validate_state(state)
	if not issue.is_empty(): return _failure("invalid_state", issue)
	if role < 0 or role >= ROLES or field < FIRST_EFFECT or field > LAST_EFFECT:
		return _failure("invalid_stat", "role or modifier-backed field is outside the recovered layout")
	var value: int = _signed(int(state.role_words[field * ROLES + role]))
	for slot in range(FIRST_SLOT, LAST_SLOT + 1):
		value += int(state.modifiers[_modifier_index(role, slot, field)])
		if value < -32768 or value > 32767:
			var failed: Dictionary = _failure("i2_overflow", "checked I2 addition overflow in equipment stat getter")
			failed.diagnostic.slot = slot; failed.diagnostic.field = field; failed.diagnostic.role = role
			return failed
	return {"value": value}

func run_equipped_entry(state: Dictionary, role: int, equipment_field: int, step_budget: int = MAX_STEPS) -> Dictionary:
	var issue: String = validate_state(state)
	if not issue.is_empty(): return _failure("invalid_state", issue)
	if role < 0 or role >= ROLES or equipment_field < 11 or equipment_field > 16:
		return _failure("invalid_context", "equipment entry requires a source role and one of fields 11..16")
	if step_budget < 1 or step_budget > MAX_STEPS: return _failure("invalid_budget", "equipment instruction budget must be 1..1024")
	var object_id: int = state.role_words[equipment_field * ROLES + role]
	# The original initialization caller executes only signed item IDs > 0.
	if _signed(object_id) <= 0:
		return {"state": state.duplicate(true), "entry": 0, "return_entry": 0, "object_id": object_id, "trace": [], "skipped_nonpositive_item": true}
	if object_id >= int(_receipt.object_count): return _failure("invalid_object", "equipped source object is outside SSS2")
	var entry: int = state.equip_entries[object_id]
	var candidate: Dictionary = state.duplicate(true)
	var pc: int = entry; var trace: Array = []
	# Entry zero is the trigger owner's null entry, independent of record 0000.
	if entry == 0: return {"state": candidate, "entry": entry, "return_entry": entry, "object_id": object_id, "trace": trace}
	while trace.size() < step_budget:
		if pc < 0 or pc >= int(_receipt.instruction_count):
			return _failure("invalid_pc", "equipment PC is outside SSS4", pc, [], trace.size())
		var words: Array = _scripts.slice(pc * 4, pc * 4 + 4)
		var opcode: int = words[0]
		var row: Dictionary = {"pc": pc, "words": words.duplicate()}
		match opcode:
			0x0000:
				trace.append(row)
				# 0000 returns the saved entry to this object's ByRef equip field.
				candidate.equip_entries[object_id] = entry
				return {"state": candidate, "entry": entry, "return_entry": entry, "object_id": object_id, "trace": trace}
			0x0017:
				var slot: int = words[1]; var field: int = words[2]
				if slot < FIRST_SLOT or slot > LAST_SLOT or field < FIRST_EFFECT or field > LAST_EFFECT:
					return _failure("invalid_effect_address", "0017 target is outside the seven-slot modifier table", pc, words, trace.size())
				var index: int = _modifier_index(role, slot, field)
				row.before = candidate.modifiers[index]; row.after = _signed(int(words[3]))
				candidate.modifiers[index] = row.after
			0x0018:
				var slot: int = words[1]; var replacement: int = words[2]
				if slot < 11 or slot > 16:
					return _failure("invalid_equipment_address", "0018 target is outside the six equipment fields", pc, words, trace.size())
				var previous: int = candidate.role_words[slot * ROLES + role]
				candidate.previous_item = previous
				for field in range(FIRST_EFFECT, LAST_EFFECT + 1): candidate.modifiers[_modifier_index(role, slot, field)] = 0
				candidate.role_words[slot * ROLES + role] = replacement
				# This opcode itself does not debit or credit inventory. That belongs
				# to its caller; new-game execution must not invent a bag deduction.
				row.equipment_field = slot; row.previous_item = previous; row.replacement_item = replacement
			0x001A:
				var field: int = words[1]; var target: int = _signed(int(words[3]))
				if target < 0:
					return _failure("negative_role_selector_unimplemented", "001A negative role selector is outside the verified subset", pc, words, trace.size())
				if target == 0 and field in [1, 65]:
					return _failure("party_battle_field_unimplemented", "001A current-target field 1/65 requires the party battle-record owner", pc, words, trace.size())
				var selected_role: int = target - 1 if target > 0 else role
				if selected_role < 0 or selected_role >= ROLES or field < 0 or field >= ROLE_FIELDS:
					return _failure("invalid_role_address", "001A role field is outside the six-role DATA3 layout", pc, words, trace.size())
				var index: int = field * ROLES + selected_role
				row.target_role = selected_role; row.role_field = field
				row.before = candidate.role_words[index]; row.after = words[2]
				candidate.role_words[index] = row.after
			_:
				return _failure("unsupported_opcode", "equipment opcode %04X is not implemented by this subset" % opcode, pc, words, trace.size())
		trace.append(row); pc = (pc + 1) & 65535
		if pc == 0:
			# The trigger owner's U2 increment can wrap. A null current PC exits
			# without fetching record zero and writes zero back to the caller.
			candidate.equip_entries[object_id] = 0
			return {"state": candidate, "entry": entry, "return_entry": 0, "object_id": object_id, "trace": trace}
	return _failure("step_budget", "equipment instruction budget exhausted before return", pc, [], trace.size())
