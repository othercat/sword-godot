# SPDX-License-Identifier: MIT
extends RefCounted
## Bounded, independently written execution of recovered equipment-entry actions.
## This is an internal kernel, not Native package/save admission or
## the complete 0075 party rebuild. No source game code is loaded or evaluated.
const ROLES = 6
const ROLE_FIELDS = 75
const FIRST_SLOT = 11
const LAST_SLOT = 17
const FIRST_EFFECT = 17
const LAST_EFFECT = 30
const MODIFIER_COUNT = ROLES * 7 * 14
const MAX_STEPS = 1024
const INVENTORY_SLOTS = 256
const INVENTORY_RECORD_BYTES = 6
const PROFILE = "pal98.equipment-entry-subset.v2"
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

static func _party_issue(roles: Array) -> String:
	# This models a legacy three-slot party only; it is not a Native party limit.
	if roles.is_empty() or roles.size() > 3: return "source party requires 1..3 members"
	var seen: Array = []
	for role in roles:
		if typeof(role) != TYPE_INT or role < 0 or role >= ROLES or role in seen: return "source party role is invalid or repeated"
		seen.append(role)
	return ""

func initial_state(party_roles: Array = [0]) -> Dictionary:
	if _receipt.is_empty() or not _party_issue(party_roles).is_empty(): return {}
	var effects: Array = []; effects.resize(MODIFIER_COUNT); effects.fill(0)
	var entries: Array = []
	for index in range(int(_receipt.object_count)): entries.append(_objects[index * 7 + 3])
	var fields: Array = []; var statuses: Array = []
	for role in party_roles:
		# A projection of the two consumed G05CC fields, not a guessed record stride.
		fields.append({"battle_sprite_word": 0, "cooperative_magic_word": 0})
		var row: Array = []; row.resize(9); row.fill(0); statuses.append(row)
	return {"source_id": _receipt.source_id, "role_words": _roles.duplicate(),
		"modifiers": effects, "equip_entries": entries, "previous_item": 0,
		"party_roles": party_roles.duplicate(), "party_fields": fields,
		"party_statuses": statuses, "trigger_success_word": 0}

func validate_state(state: Dictionary) -> String:
	if _receipt.is_empty(): return "source tables have not been read"
	if state.size() != 9 or state.get("source_id") != _receipt.source_id:
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
	if not state.get("party_roles") is Array: return "source party roles must be an array"
	var issue: String = _party_issue(state.party_roles)
	if not issue.is_empty(): return issue
	if not state.get("party_fields") is Array or not state.get("party_statuses") is Array:
		return "source party fields and statuses must be arrays"
	if state.party_fields.size() != state.party_roles.size() or state.party_statuses.size() != state.party_roles.size():
		return "source party projection must match member count"
	for slot in range(state.party_roles.size()):
		var fields = state.party_fields[slot]; var statuses = state.party_statuses[slot]
		if not fields is Dictionary or fields.size() != 2: return "source party field projection has the wrong shape"
		for key in ["battle_sprite_word", "cooperative_magic_word"]:
			if typeof(fields.get(key)) != TYPE_INT or fields[key] < 0 or fields[key] > 65535: return "source party field is not a WORD"
		if not statuses is Array or statuses.size() != 9: return "source party status row requires nine I2 values"
		for duration in statuses:
			if typeof(duration) != TYPE_INT or duration < -32768 or duration > 32767: return "source status duration is not signed I2"
	if typeof(state.get("trigger_success_word")) != TYPE_INT or state.trigger_success_word < -32768 or state.trigger_success_word > 32767:
		return "trigger success word is not signed I2"
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

func rebuild_party_equipment(state: Dictionary) -> Dictionary:
	var cleared: Dictionary = clear_original_modifier_prefix(state)
	if cleared.has("error"): return cleared
	var candidate: Dictionary = cleared.state; var entries: Array = []
	# Finish each member before copying the next member's base fields: a source
	# equipment script may assign another role's base before that copy happens.
	for slot in range(candidate.party_roles.size()):
		var role: int = candidate.party_roles[slot]
		candidate.role_words[4 * ROLES + role] = 0
		candidate.party_fields[slot].battle_sprite_word = candidate.role_words[1 * ROLES + role]
		candidate.party_fields[slot].cooperative_magic_word = candidate.role_words[65 * ROLES + role]
		candidate.party_statuses[slot][8] = 0
		for field in range(11, 17):
			var result: Dictionary = run_equipped_entry(candidate, role, field)
			if result.has("error"):
				result.diagnostic.party_slot = slot; result.diagnostic.role = role
				return result
			candidate = result.state
			entries.append({"party_slot": slot, "role": role, "equipment_field": field,
				"object_id": result.object_id, "entry": result.entry, "return_entry": result.return_entry, "trace": result.trace})
	return {"state": candidate, "entries": entries}

func prepare_party_equipment(state: Dictionary, inventory_bytes: PackedByteArray) -> Dictionary:
	# The inventory owner supplies all 256 records explicitly. Do not derive a
	# new-game bag from equipment, discard empty slots, or reinterpret signed bits.
	if inventory_bytes.size() != INVENTORY_SLOTS * INVENTORY_RECORD_BYTES:
		var result: Dictionary = _failure("invalid_inventory_layout", "inventory requires 256 six-byte records")
		result.diagnostic.size_bytes = inventory_bytes.size(); return result
	var inventory: PackedByteArray = inventory_bytes.duplicate()
	for slot in range(INVENTORY_SLOTS): inventory.encode_u16(slot * INVENTORY_RECORD_BYTES + 4, 0)
	# Original order is usage clear, modifier-prefix clear, then member-by-member
	# equipment execution. Native publishes only a complete candidate; this safety
	# boundary is not a claim about rollback after an original VB/resource error.
	var result: Dictionary = rebuild_party_equipment(state)
	if result.has("error"):
		result.diagnostic.preparation_phase = "equipment"; return result
	result.inventory_bytes = inventory
	return result

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
	var party_slot: int = state.party_roles.find(role)
	if party_slot < 0: return _failure("invalid_context", "equipment role must resolve through the current source party")
	if step_budget < 1 or step_budget > MAX_STEPS: return _failure("invalid_budget", "equipment instruction budget must be 1..1024")
	var object_id: int = state.role_words[equipment_field * ROLES + role]
	# The original initialization caller executes only signed item IDs > 0.
	if _signed(object_id) <= 0:
		return {"state": state.duplicate(true), "entry": 0, "return_entry": 0, "object_id": object_id, "trace": [], "skipped_nonpositive_item": true}
	if object_id >= int(_receipt.object_count): return _failure("invalid_object", "equipped source object is outside SSS2")
	var entry: int = state.equip_entries[object_id]
	var candidate: Dictionary = state.duplicate(true)
	# This belongs to the trigger caller, not to opcode 002D. Skipped nonpositive
	# items above never enter that caller and retain the previous success word.
	candidate.trigger_success_word = -1
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
				var selected_role: int = target - 1 if target > 0 else role
				if selected_role < 0 or selected_role >= ROLES or field < 0 or field >= ROLE_FIELDS:
					return _failure("invalid_role_address", "001A role field is outside the six-role DATA3 layout", pc, words, trace.size())
				if target == 0 and field in [1, 65]:
					var key: String = "battle_sprite_word" if field == 1 else "cooperative_magic_word"
					row.party_slot = party_slot; row.party_field = key
					row.before = candidate.party_fields[party_slot][key]; row.after = words[2]
					candidate.party_fields[party_slot][key] = row.after
				else:
					var index: int = field * ROLES + selected_role
					row.target_role = selected_role; row.role_field = field
					row.before = candidate.role_words[index]; row.after = words[2]
					candidate.role_words[index] = row.after
			0x002D:
				var status: int = _signed(int(words[1])); var duration: int = _signed(int(words[2]))
				if status < 0 or status >= 9:
					return _failure("invalid_status_address", "002D status is outside the nine-slot source status table", pc, words, trace.size())
				var previous: int = candidate.party_statuses[party_slot][status]
				if status == 4:
					if _signed(int(candidate.role_words[9 * ROLES + role])) <= 0:
						return _failure("status4_render_unimplemented", "002D status4 with nonpositive HP requires the original four-frame render and RNG owner", pc, words, trace.size())
					candidate.trigger_success_word = 0
				elif (status > 4 or previous <= 0) and previous < duration:
					candidate.party_statuses[party_slot][status] = duration
				# Arg2 is not read by the original case. Status identity is indexed
				# by party slot, unlike base role fields and equipment modifiers.
				row.party_slot = party_slot; row.status_slot = status
				row.before = previous; row.after = candidate.party_statuses[party_slot][status]
				row.trigger_success_word = candidate.trigger_success_word
			_:
				return _failure("unsupported_opcode", "equipment opcode %04X is not implemented by this subset" % opcode, pc, words, trace.size())
		trace.append(row); pc = (pc + 1) & 65535
		if pc == 0:
			# The trigger owner's U2 increment can wrap. A null current PC exits
			# without fetching record zero and writes zero back to the caller.
			candidate.equip_entries[object_id] = 0
			return {"state": candidate, "entry": entry, "return_entry": 0, "object_id": object_id, "trace": trace}
	return _failure("step_budget", "equipment instruction budget exhausted before return", pc, [], trace.size())
