# SPDX-License-Identifier: MIT
extends SceneTree
## The party condition backing has one truth: sixteen status columns per party
## slot (G06C4) plus sixteen 4-byte poison records per party slot (G0704, WORD
## id + WORD script). Addressing stays by party slot through reorders, corrupt
## or missing backing is named-rejected, and the 0075 expansion materializes
## zeroed rows of the same shape.
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

	# initial_state carries the full 16-column and 16-record backing, zeroed.
	var state: Dictionary = {"equipment": kernel.initial_state([0, 1, 3])}
	var equipment: Dictionary = state.equipment
	check(equipment.party_statuses.size() == 3 and equipment.party_poisons.size() == 3
		and equipment.party_statuses[0].size() == 16
		and equipment.party_poisons[0] is PackedByteArray and equipment.party_poisons[0].size() == 64
		and equipment.party_poisons[0] == _zero(64),
		"initial state materializes three zeroed 16-column and 16-record rows")
	check(kernel.validate_state(equipment) == "",
		"the expanded backing validates: " + kernel.validate_state(equipment))

	# Sentinel values across every column and record, addressed by party slot.
	for column in range(16): equipment.party_statuses[1][column] = 100 + column
	for record in range(16):
		equipment.party_poisons[1].encode_u16(record * 4, 200 + record)
		equipment.party_poisons[1].encode_u16(record * 4 + 2, 3000 + record)
	var sentinel_ok: bool = true
	for column in range(16): sentinel_ok = sentinel_ok and equipment.party_statuses[1][column] == 100 + column
	for record in range(16):
		sentinel_ok = sentinel_ok and equipment.party_poisons[1].decode_u16(record * 4) == 200 + record
		sentinel_ok = sentinel_ok and equipment.party_poisons[1].decode_u16(record * 4 + 2) == 3000 + record
	check(sentinel_ok, "all sixteen status columns and poison id/script pairs round-trip")
	check(kernel.validate_state(equipment) == "" and equipment.party_poisons[0] == _zero(64),
		"the sentinels stay valid and leave the sibling slot zeroed")

	# Poison records ride the state through the real rebuild untouched.
	var rebuilt: Dictionary = kernel.rebuild_party_equipment(equipment)
	check(not rebuilt.has("error") and rebuilt.state.party_poisons == equipment.party_poisons,
		"the equipment rebuild keeps every poison record")

	# Missing, short, mistyped or trailing poison backing is named-rejected.
	var missing: Dictionary = {"equipment": equipment.duplicate(true)}
	missing.equipment.erase("party_poisons")
	check(kernel.validate_state(missing.equipment) != "", "a missing poison backing is rejected")
	var short: Dictionary = {"equipment": equipment.duplicate(true)}
	short.equipment.party_poisons[2] = short.equipment.party_poisons[2].slice(0, 63)
	check(str(kernel.validate_state(short.equipment)).contains("sixteen id/script"),
		"a 63-byte poison row is rejected: " + kernel.validate_state(short.equipment))
	var mistyped: Dictionary = {"equipment": equipment.duplicate(true)}
	mistyped.equipment.party_poisons[0] = [0, 0]
	check(str(kernel.validate_state(mistyped.equipment)).contains("sixteen id/script"),
		"a non-byte poison row is rejected")
	var thin: Dictionary = {"equipment": equipment.duplicate(true)}
	thin.equipment.party_poisons.pop_back()
	check(str(kernel.validate_state(thin.equipment)).contains("match member count"),
		"a poison backing shorter than the projection is rejected")
	var narrow: Dictionary = {"equipment": equipment.duplicate(true)}
	narrow.equipment.party_statuses[0].pop_back()
	check(str(kernel.validate_state(narrow.equipment)).contains("sixteen I2"),
		"a fifteen-column status row is rejected")

	# 0075 growth materializes zeroed backing rows and shrink slices every array;
	# the composition sequence is the lifecycle's 1 -> 3 -> 1 -> 2.
	var party: Dictionary = {"globals": {"current_scene": 1, "battle_mode": 0, "member_last": 0,
			"follower_count": 0, "trigger_success_word": 0},
		"equipment": kernel.initial_state([0]),
		"party_records": [{"role_id": 0, "screen_x": 160, "screen_y": 112, "current_frame": 3},
			{"role_id": 0, "screen_x": 160, "screen_y": 112, "current_frame": 3},
			{"role_id": 0, "screen_x": 160, "screen_y": 112, "current_frame": 3}],
		"inventory_bytes": _zero(1536)}
	party.equipment.party_poisons[0].encode_u16(0, 44)
	var grown: Dictionary = commands.consume(party, {"words": [0x0075, 1, 2, 3], "entry": 1, "event_id": 0})
	check(not grown.has("error") and party.equipment.party_statuses.size() == 3
		and party.equipment.party_poisons.size() == 3
		and party.equipment.party_poisons[1] == _zero(64)
		and party.equipment.party_statuses[2][15] == 0,
		"the 0075 growth materializes zeroed backing rows: " + str(grown.get("error", "")))
	check(party.equipment.party_poisons[0].decode_u16(0) == 44,
		"the pre-existing slot zero poison survives the growth")
	var shrunk: Dictionary = commands.consume(party, {"words": [0x0075, 1, 0, 0], "entry": 1, "event_id": 0})
	var regrown: Dictionary = commands.consume(party, {"words": [0x0075, 1, 2, 0], "entry": 1, "event_id": 0})
	check(not shrunk.has("error") and not regrown.has("error")
		and party.equipment.party_poisons.size() == 2 and party.equipment.party_statuses.size() == 2
		and party.equipment.party_poisons[0].decode_u16(0) == 44,
		"the 1 -> 3 -> 1 -> 2 cycle keeps the backing shapes and slot zero content")

	# Poison records are slot-addressed: swapping the role projection must not
	# migrate any slot's records, and slots never alias each other.
	party.equipment.party_poisons[1].encode_u16(0, 7)
	party.equipment.party_roles = [3, 1]
	check(party.equipment.party_poisons[1].decode_u16(0) == 7
		and party.equipment.party_poisons[0].decode_u16(0) == 44,
		"the reorder keeps both slots' poison records in place")
	party.equipment.party_poisons[1] = PackedByteArray([1, 2, 3])
	var refused: Dictionary = commands.consume(party, {"words": [0x0075, 1, 2, 0], "entry": 1, "event_id": 0})
	check(refused.has("error") and str(refused.error).contains("poison rows"),
		"a corrupt poison row refuses the growth: " + str(refused.get("error", "")))

	var output: Dictionary = {"suite": "test_pal98_status_backing", "checks": results,
		"passed": results.size() - failed, "failed": failed}
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n"); file.close()
	print("PASS %d/%d" % [results.size() - failed, results.size()])
	quit(1 if failed > 0 else 0)
