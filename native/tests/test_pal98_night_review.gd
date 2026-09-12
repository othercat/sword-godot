# SPDX-License-Identifier: MIT
extends "res://tests/test_pal98_enter_script.gd"
## Independent regressions for the e757e80 review. Synthetic byte sentinels and
## acknowledged host requests prove arithmetic/state order, not screen output.
const PaletteOwner = preload("res://src/native_pal98_palette.gd")

func _request(opcode: int, args: Array = [0, 0, 0], context: int = 0) -> Dictionary:
	return {"words": [opcode, args[0], args[1], args[2]], "entry": 1, "event_id": context}

func _palette_state() -> Dictionary:
	var bytes: PackedByteArray = _zero(0xC00)
	for index in range(0x300, 0x600): bytes[index] = 63
	return {"globals": {"day_night_word": 0, "fade_gate_word": 7}, "palette_bytes": bytes}

func _arithmetic() -> void:
	var palette = PaletteOwner.new()
	# PALOLD cmp AH,AL uses signed JG. The ascending path's ADD 2 falls
	# through DEC, giving a net +1. These expectations cover both byte signs.
	for vector in [[0, 63, 1], [62, 63, 63], [63, 0, 62], [255, 0, 0],
			[0, 255, 255], [128, 127, 129], [127, 128, 126], [63, 63, 63]]:
		var bytes: PackedByteArray = _zero(0xC00)
		bytes[0x300] = vector[0]; bytes[0] = vector[1]
		var result: Dictionary = palette.converge_pair(bytes, 0x300, 0)
		check(not result.has("error") and bytes[0x300] == vector[2],
			"cvpate signed one-step vector " + str(vector))

func _fade_requests(commands) -> void:
	for argument in [5, 0]:
		var state: Dictionary = _palette_state()
		var result: Dictionary = commands.consume(state, _request(0x0080, [argument, 0, 0]))
		var installs: Array = []; var waits: int = 0; var events: int = 0; var frames: int = 0
		var final_gate: int = -999; var final_bytes: int = -999
		for step in range(128):
			for request in result.get("requests", []):
				match request.kind:
					"apply_palette":
						installs.append(request.offset)
						if request.offset == 0x180:
							final_gate = state.globals.fade_gate_word
							final_bytes = request.bytes[0]
					"fade_wait": waits += 1
					"fade_event_pump": events += 1
					"fade_frame": frames += 1
			if not result.has("pending"): break
			# Simulate a state write on the last round's wait/frame receipt.
			# The final install must be constructed after that receipt.
			if installs.size() == 32: state.palette_bytes[0x300] = 21
			result = commands.continue_command(result.pending, state)
		check(installs.count(0x300) == 32 and installs.count(0x180) == 1,
			"0080 publishes 32 work installs and one final install: A0=" + str(argument))
		check((waits == 32 and events == 0 and frames == 0) if argument > 0 else
			(waits == 0 and events == 32 and frames == 32),
			"0080 keeps the last round's wait or event/frame calls: A0=" + str(argument))
		check(final_gate == 7 and state.globals.fade_gate_word == 0,
			"0080 clears the gate only after the final install receipt: A0=" + str(argument))
		check(final_bytes == 21, "0080 final bytes include last-round host writeback: A0=" + str(argument))
		check(state.palette_bytes[0x600] == 32, "0080 advances by one in each of 32 rounds: A0=" + str(argument))

	# The WORD-indexed windows are separate. Use a nonuniform RGB sentinel
	# so a uniform fixture cannot hide reversed cvpate arguments.
	for swapped in [0, 1]:
		var state: Dictionary = _palette_state()
		state.palette_bytes.fill(0)
		state.palette_bytes[15] = 40; state.palette_bytes[16] = 41; state.palette_bytes[17] = 42
		var result: Dictionary = commands.consume(state, _request(0x008C, [5, 3, swapped]))
		var offset: int = 0x480 if swapped == 0 else 0x300
		var index: int = 600
		var expected: int = 1 if swapped == 0 else 39
		check(not result.has("error") and result.requests[0].offset == offset
			and result.requests[0].bytes[index] == expected,
			"008C converges the block it installs: swapped=" + str(swapped))

func _state_refusals(commands, source) -> void:
	for defect in ["missing_member", "duplicate_role", "role_word", "status_word"]:
		var state: Dictionary = _fixture(source)
		state.equipment.role_words.fill(0); state.equipment.role_words[7 * 6] = 50
		match defect:
			"missing_member": state.equipment.party_roles = [0]; state.globals.member_last = 1
			"duplicate_role": state.equipment.party_roles = [0, 0, 3]
			"role_word": state.equipment.role_words[449] = 65536
			"status_word": state.equipment.party_statuses[0][15] = 0.5
		var before: Dictionary = state.duplicate(true)
		var result: Dictionary = commands.consume(state, _request(0x0022, [1, 1, 0]))
		check(result.has("error") and state == before,
			"0022 rejects invalid backing without changing HP/status: " + defect)
	var invalid: Dictionary = _fixture(source)
	invalid.equipment.role_words.fill(0); invalid.equipment.role_words[11 * 6] = 65566
	var old: Dictionary = invalid.duplicate(true)
	var unequip: Dictionary = commands.consume(invalid, _request(0x0023, [0, 1, 0]))
	check(unequip.has("error") and invalid == old, "0023 does not turn an invalid WORD into item30")

	for defect in ["formation", "late_record", "late_trail"]:
		var state: Dictionary = _fixture(source)
		var args: Array = [32, 64, 0]
		match defect:
			"formation": state.globals.party_x = 32752; args = [1023, 64, 1]
			"late_record": state.party_records[4] = null
			"late_trail": state.party_trail[4] = null
		var before: Dictionary = state.duplicate(true)
		var result: Dictionary = commands.consume(state, _request(0x0046, args))
		check(result.has("error") and state == before,
			"0046 late failure keeps globals, records and trail unchanged: " + defect)

func _lifecycle(commands, source) -> void:
	var state: Dictionary = _fixture(source)
	state.equipment.role_words.fill(0)
	state.equipment.party_statuses[1][0] = 5
	state.equipment.party_statuses[1][15] = 7
	state.equipment.party_poisons[1].encode_u16(0, 44)
	state.equipment.party_poisons[1].encode_u16(2, 777)
	var small: Dictionary = commands.consume(state, _request(0x0075, [1, 0, 0]))
	var big: Dictionary = commands.consume(state, _request(0x0075, [1, 2, 4]))
	check(not small.has("error") and not big.has("error")
		and state.equipment.party_statuses[1][0] == 5 and state.equipment.party_statuses[1][15] == 7,
		"0075 shrink/regrow retains slot-indexed condition durations")
	check(state.equipment.party_poisons[1].decode_u16(0) == 44
		and state.equipment.party_poisons[1].decode_u16(2) == 777,
		"0075 shrink/regrow retains both inactive poison words")

func _owner_recovery() -> void:
	var source = _source([0], [1], [[0x0080, 5, 0, 0], [0x0001, 0, 0, 0]])
	var owner = Enter.new(); owner.load_source(source)
	var state: Dictionary = _fixture(source)
	var first: Dictionary = owner.start(state, 1, 1)
	var old_id: String = first.request.id
	var failed_run: Dictionary = owner.resume(old_id, {"error": "independent palette host failure"})
	var again: Dictionary = owner.start(state, 1, 1)
	check(failed_run.has("error") and not failed_run.has("state") and again.has("request"),
		"palette host failure discards the candidate and permits restarting the same Enter owner")
	check(owner.resume(old_id, {"completed": true}).has("error"), "old palette receipts remain invalid after restart")
	var driven: Dictionary = _drive(owner, again)
	check(driven.result.has("return_entry"), "real Trigger completes after all palette receipts")
	state.globals.fade_gate_word = 7
	var last_install: Dictionary = owner.start(state, 1, 1)
	for step in range(128):
		if not last_install.has("request"): break
		var request: Dictionary = last_install.request
		if request.kind == "apply_palette" and request.get("offset") == 0x180: break
		last_install = owner.resume(request.id, {"completed": true, "state": request.state})
	check(last_install.has("request") and last_install.request.state.globals.fade_gate_word == 7,
		"real Enter final install still sees the original gate before acknowledgment")
	if last_install.has("request"):
		var refused: Dictionary = owner.resume(last_install.request.id, {"error": "final install refused"})
		check(refused.has("error") and not refused.has("state") and state.globals.fade_gate_word == 7,
			"a failed final install publishes neither the offset nor the gate candidate")

func _malformed_backing(commands, source) -> void:
	for defect in ["role_length", "role_type", "role_bool", "party_type", "status_outer",
			"status_short", "status_bool", "poison_outer", "poison_short", "poison_type"]:
		var state: Dictionary = _fixture(source)
		state.equipment.role_words.fill(0); state.equipment.role_words[7 * 6] = 50
		match defect:
			"role_length": state.equipment.role_words.pop_back()
			"role_type": state.equipment.role_words[449] = "1"
			"role_bool": state.equipment.role_words[54] = false
			"party_type": state.equipment.party_roles = 0
			"status_outer": state.equipment.party_statuses = []
			"status_short": state.equipment.party_statuses[2].pop_back()
			"status_bool": state.equipment.party_statuses[2][15] = false
			"poison_outer": state.equipment.party_poisons = []
			"poison_short": state.equipment.party_poisons[2] = _zero(63)
			"poison_type": state.equipment.party_poisons[2] = []
		var before: Dictionary = state.duplicate(true)
		var result = commands.consume(state, _request(0x0022, [1, 1, 0]))
		check(result is Dictionary and result.has("error") and state == before,
			"0022 malformed backing returns a diagnostic before any write: " + defect)
	for word in [-1, false, "30", 65536]:
		var state: Dictionary = _fixture(source)
		state.equipment.role_words[11 * 6] = word
		var before: Dictionary = state.duplicate(true)
		var result = commands.consume(state, _request(0x0023, [0, 1, 0]))
		check(result is Dictionary and result.has("error") and state == before,
			"0023 invalid role WORD is not converted: " + str(word))
	for defect in ["poison", "status", "roles"]:
		var state: Dictionary = _fixture(source)
		var arguments: Array = [2, 1, 0]
		match defect:
			"poison": state.equipment.party_poisons[2] = _zero(63)
			"status": state.equipment.party_statuses[2][15] = false
			"roles": arguments = [1, 1, 0]
		var before: Dictionary = state.duplicate(true)
		var result = commands.consume(state, _request(0x0075, arguments))
		check(result.has("error") and state == before, "0075 validates before changing member identity: " + defect)
	for opcode in [0x0080, 0x008C]:
		for defect in ["short", "absent", "type"]:
			var state: Dictionary = _palette_state()
			var result = commands.consume(state, _request(opcode))
			match defect:
				"short": state.palette_bytes = _zero(767)
				"absent": state.erase("palette_bytes")
				"type": state.palette_bytes = []
			var before: Dictionary = state.duplicate(true)
			var pending: Dictionary = result.pending.duplicate(true)
			var continued = commands.continue_command(result.pending, state)
			check(continued is Dictionary and continued.has("error") and state == before and result.pending == pending,
				"palette host backing is revalidated before advancing: " + str(opcode) + "/" + defect)

	# A real equipment rebuild clears status8 only on the active slots. Keep
	# inactive conditions through 3 -> 1 -> 3 without involving sprite doubles.
	var kernel = Equipment.new()
	kernel.read_tables(source.copy_chunk("data", 3), source.copy_chunk("sss", 2), source.copy_chunk("sss", 4))
	var host = EntryHost.new(); host.bind(RefCounted.new(), kernel, _zero(1536), [0, 0, 0, 0, 0, 0])
	var state: Dictionary = _fixture(source); state.equipment.role_words.fill(0)
	state.equipment.party_statuses[1][8] = 6; state.equipment.party_statuses[1][15] = 7
	state.equipment.party_poisons[1].encode_u16(0, 44); state.equipment.party_poisons[1].encode_u16(2, 777)
	commands.consume(state, _request(0x0075, [1, 0, 0]))
	var small = host.answer({"kind": "rebuild_party_equipment", "state": state})
	check(small.get("completed", false) and state.equipment.party_statuses[1][8] == 6,
		"real T156 owner does not clear an inactive slot's equipment status")
	commands.consume(state, _request(0x0075, [1, 2, 4]))
	var large = host.answer({"kind": "rebuild_party_equipment", "state": state})
	check(large.get("completed", false) and state.equipment.party_statuses[1][8] == 0
		and state.equipment.party_statuses[1][15] == 7 and state.equipment.party_poisons[1].decode_u16(0) == 44
		and state.equipment.party_poisons[1].decode_u16(2) == 777,
		"real T156 rebuild on regrowth clears status8 and retains poison plus other statuses")

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]): quit(2); return
	var admitted = Package.new()
	if not admitted.load_package(args[0]): quit(2); return
	var commands = Commands.new(); commands.load_source(admitted.pal98_sources)
	_arithmetic(); _fade_requests(commands); _state_refusals(commands, admitted.pal98_sources)
	_lifecycle(commands, admitted.pal98_sources); _owner_recovery()
	_malformed_backing(commands, admitted.pal98_sources)
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify({"suite": "test_pal98_night_review", "checks": checks,
		"passed": checks.size() - failed, "failed": failed}, "  ") + "\n"); file.close()
	print("Night review: %d/%d" % [checks.size() - failed, checks.size()]); quit(1 if failed else 0)
