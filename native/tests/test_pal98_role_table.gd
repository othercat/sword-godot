# SPDX-License-Identifier: MIT
extends SceneTree
## DSA-R01/R04 cross-module guard: the DATA3 role table keeps the real
## field*6+role layout through the producers (0x0065/0x001A), the entry host
## sprite projection and the equipment kernel stat consumer. Distinct sentinels
## per (field, role) plus the real admitted table prove the index arithmetic,
## not a matching wrong receipt.
const Commands = preload("res://src/native_pal98_script_commands.gd")
const Equipment = preload("res://src/native_pal98_equipment_kernel.gd")
const EntryHost = preload("res://src/native_pal98_entry_host.gd")
const Package = preload("res://src/native_package.gd")

var results: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	results.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

## Recording sprite-cache double: load_party only records the projected ids,
## so this file checks the host's projection arithmetic, not the cache owner.
class CacheDouble:
	var last_ids: Array = []
	func load_party(_member_last: int, _follower_count: int, party_records: Array, ids: Array) -> Dictionary:
		last_ids = ids.duplicate()
		return {"party_records": party_records, "loaded_mgo_chunks": [], "used_words": 0}

func _sentinel(field: int, role: int) -> int:
	return (field + 1) * 100 + (role + 1)

func _zero(count: int) -> PackedByteArray:
	var bytes = PackedByteArray(); bytes.resize(count); return bytes

func _globals() -> Dictionary:
	return {"current_scene": 1, "battle_mode": 0, "member_last": 2, "follower_count": 0}

func _sentinel_state(kernel) -> Dictionary:
	var equipment: Dictionary = kernel.initial_state([0, 1, 3])
	var words: Array = []
	for field in range(75):
		for role in range(6):
			words.append(_sentinel(field, role))
	equipment.role_words = words
	return {"globals": _globals(), "equipment": equipment, "party_records": []}

func _consume(commands, state: Dictionary, opcode: int, a0: int, a1: int, a2: int) -> Dictionary:
	return commands.consume(state, {"words": [opcode, a0, a1, a2], "entry": 1, "event_id": 0})

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

	# The admitted real table keeps field*6+role: field 2 (map sprite) of the six
	# roles sits at words 12..17 as [2,3,7,525,5,26]; word 2 is field 0 of role 2.
	var real_state: Dictionary = kernel.initial_state([0])
	var real_words: Array = real_state.role_words
	check(real_words.size() == 450, "the real role word table has 450 words")
	check(real_words[12] == 2 and real_words[2] != real_words[12],
		"the real DATA3 table reads field-major: word12 is role0's map sprite, not the role-major word")
	check([real_words[12], real_words[13], real_words[14], real_words[15], real_words[16], real_words[17]]
		== [2, 3, 7, 525, 5, 26],
		"the reviewed source sprite row [2,3,7,525,5,26] sits at field2*6+role")

	# 0x0065 producer: role0 sprite 193 lands on word 12 and leaves word 2 alone;
	# role5 sprite 998 lands on word 17.
	var word2_before: int = real_words[2]
	var state_0065: Dictionary = {"globals": _globals(), "equipment": kernel.initial_state([0, 1, 3]), "party_records": []}
	var written = _consume(commands, state_0065, 0x0065, 0, 193, 0)
	check(not written.has("error") and written.state.equipment.role_words[12] == 193
		and written.state.equipment.role_words[2] == word2_before,
		"0x0065 role0 writes field2*6+role0 and keeps the role-major word: " + str(written.get("error", "")))
	var role5_write = _consume(commands, written.state, 0x0065, 5, 998, 0)
	check(not role5_write.has("error") and role5_write.state.equipment.role_words[17] == 998,
		"0x0065 role5 writes field2*6+role5=17: " + str(role5_write.get("error", "")))

	# Host consumer: the load_party_sprites projection reads exactly those words,
	# mixing the two 0x0065 writes with the untouched real row.
	var host = EntryHost.new()
	if not host.bind(CacheDouble.new(), kernel, _zero(1536), [0, 0, 0, 0, 0, 0]):
		push_error("host bind failed: " + str(host.error)); quit(2); return
	var host_state: Dictionary = role5_write.state
	host_state.globals.member_last = 0; host_state.globals.follower_count = 0
	var answered = host.answer({"kind": "load_party_sprites", "state": host_state})
	check(answered.get("completed", false), "the host answers load_party_sprites: " + str(answered.get("error", "")))
	var ids: Array = []
	for receipt in host.answered():
		if receipt.kind == "load_party_sprites": ids = receipt.role_sprite_ids
	check(ids == [193, 3, 7, 525, 5, 998],
		"the host projects load_party_sprites ids from field2*6+role: " + str(ids))

	# 0x001A explicit selector: absolute role A2-1 in the base table, projection
	# untouched, and it resolves roles outside the active party.
	var state_001a: Dictionary = _sentinel_state(kernel)
	var explicit = _consume(commands, state_001a, 0x001A, 17, 999, 4)
	check(not explicit.has("error")
		and explicit.state.equipment.role_words[17 * 6 + 3] == 999
		and explicit.state.equipment.role_words[17 * 6] == _sentinel(17, 0),
		"0x001A positive A2=4 writes absolute role3 at field17*6+3: " + str(explicit.get("error", "")))
	var explicit_field1 = _consume(commands, explicit.state, 0x001A, 1, 123, 3)
	check(not explicit_field1.has("error")
		and explicit_field1.state.equipment.role_words[1 * 6 + 2] == 123
		and explicit_field1.state.equipment.party_fields[0].battle_sprite_word == 0,
		"the explicit branch keeps field 1 in the base table, not the G05CC word: " + str(explicit_field1.get("error", "")))
	var outside_party = _consume(commands, explicit_field1.state, 0x001A, 17, 888, 6)
	check(not outside_party.has("error")
		and outside_party.state.equipment.role_words[17 * 6 + 5] == 888,
		"a three-slot projection still resolves the absolute role5: " + str(outside_party.get("error", "")))
	var refused = _consume(commands, outside_party.state, 0x001A, 17, 7, 7)
	check(refused.has("error"), "an absolute role beyond the six-role table is refused")

	# 0x001A default-context branch: the current role slot drives the G05CC
	# special case for fields 1/65 and the party role for other fields.
	var default_state: Dictionary = _sentinel_state(kernel)
	default_state.globals.current_role_slot = 2
	var projection_write = _consume(commands, default_state, 0x001A, 1, 55, 0)
	check(not projection_write.has("error")
		and projection_write.state.equipment.party_fields[2].battle_sprite_word == 55
		and projection_write.state.equipment.role_words[1 * 6 + 3] == _sentinel(1, 3),
		"the default branch routes field 1 to slot2's projection word only: " + str(projection_write.get("error", "")))
	var magic_write = _consume(commands, projection_write.state, 0x001A, 65, 66, 0)
	check(not magic_write.has("error")
		and magic_write.state.equipment.party_fields[2].cooperative_magic_word == 66,
		"the default branch routes field 65 to the cooperative magic word")
	var default_base = _consume(commands, magic_write.state, 0x001A, 20, 77, 0)
	check(not default_base.has("error")
		and default_base.state.equipment.role_words[20 * 6 + 3] == 77
		and default_base.state.equipment.role_words[20 * 6] == _sentinel(20, 0),
		"default-branch numeric fields follow the party role at field*6+role")

	# Equipment consumer: effective_stat reads exactly what the explicit 0x001A
	# wrote (modifiers are zero in this state).
	var stat_state: Dictionary = {"globals": _globals(), "equipment": kernel.initial_state([0, 1, 3]), "party_records": []}
	var stat_write = _consume(commands, stat_state, 0x001A, 17, 99, 1)
	check(not stat_write.has("error"), "0x001A field17 role0 write succeeds: " + str(stat_write.get("error", "")))
	var stat = kernel.effective_stat(stat_write.state.equipment, 0, 17)
	check(not stat.has("error") and stat.value == 99,
		"effective_stat(0,17) consumes the explicit 0x001A write: " + str(stat))

	var passed = results.filter(func(r): return r.passed).size()
	var out = FileAccess.open(args[1], FileAccess.WRITE)
	if out == null: quit(2); return
	out.store_string(JSON.stringify({"passed": passed, "failed": failed, "checks": results}, "\t"))
	out.close()
	print("role table layout: ", results.size(), " checks, ", failed, " failed")
	quit(0 if failed == 0 else 1)
