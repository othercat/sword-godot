# SPDX-License-Identifier: MIT
extends SceneTree
## DSA-R03 guard: 0x0075 owns the party projection lifecycle. Shrinking to a
## smaller party and re-expanding (3 -> 1 -> 2 -> 3) must stay legal, with the
## real equipment owner rebuilding every row from the current base table and
## the current inventory, not a bind-time snapshot.
const Commands = preload("res://src/native_pal98_script_commands.gd")
const Equipment = preload("res://src/native_pal98_equipment_kernel.gd")
const EntryHost = preload("res://src/native_pal98_entry_host.gd")
const Package = preload("res://src/native_package.gd")

var results: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	results.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

class CacheDouble:
	func load_party(_member_last: int, _follower_count: int, party_records: Array, _ids: Array) -> Dictionary:
		return {"party_records": party_records, "loaded_mgo_chunks": [], "used_words": 0}

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
	var host = EntryHost.new()
	if not host.bind(CacheDouble.new(), kernel, _zero(1536), [0, 0, 0, 0, 0, 0]):
		push_error("host bind failed: " + str(host.error)); quit(2); return

	# A seeded bag proves rebuild reads the request's current inventory, and the
	# quantity survives every composition change.
	var bag: PackedByteArray = _zero(1536)
	bag.encode_u16(0, 196); bag.encode_u16(2, 3)
	var globals: Dictionary = {"current_scene": 1, "battle_mode": 0, "member_last": 2, "follower_count": 0}
	var party_records: Array = []
	for slot in range(5):
		party_records.append({"role_id": 0, "screen_x": 160 + slot * 16, "screen_y": 112, "current_frame": 3})
	var state: Dictionary = {"globals": globals, "equipment": kernel.initial_state([0, 1, 3]),
		"party_records": party_records, "inventory_bytes": bag}

	var compositions: Array = [{"args": [1], "roles": [0]}, {"args": [2, 3], "roles": [1, 2]},
		{"args": [1], "roles": [0]}, {"args": [1, 2, 4], "roles": [0, 1, 3]}]
	for step in compositions:
		var args_words: Array = [0x0075, 0, 0, 0]
		for index in range(step.args.size()): args_words[1 + index] = step.args[index]
		var consumed = commands.consume(state, {"words": args_words, "entry": 1, "event_id": 0})
		if consumed.has("error"):
			check(false, "0x0075 %s accepted: %s" % [str(step.args), str(consumed.get("error", ""))]); continue
		state = consumed.state
		check(state.equipment.party_roles == step.roles,
			"0x0075 %s applies the composition %s" % [str(step.args), str(state.equipment.party_roles)])
		check(state.globals.member_last == step.roles.size() - 1,
			"0x0075 %s updates member_last to %d" % [str(step.args), state.globals.member_last])
		var rebuilt = host.answer({"kind": "rebuild_party_equipment", "state": state})
		check(rebuilt.get("completed", false), "the real equipment owner rebuilds party %s: %s"
			% [str(step.roles), str(rebuilt.get("error", ""))])
		check(state.equipment.party_fields.size() == step.roles.size()
			and state.equipment.party_statuses.size() == step.roles.size(),
			"the projections after %s match the active member count" % str(step.roles))
		# Equipment scripts may legally rewrite a projection word during their own
		# rebuild, so the lifecycle rows must equal a direct rebuild of the same
		# composition, not the raw base words.
		var fresh: Dictionary = {"equipment": kernel.initial_state(step.roles),
			"inventory_bytes": bag.duplicate()}
		var fresh_rebuilt = host.answer({"kind": "rebuild_party_equipment", "state": fresh})
		check(fresh_rebuilt.get("completed", false)
			and fresh.equipment.party_fields == state.equipment.party_fields
			and fresh.equipment.party_statuses == state.equipment.party_statuses,
			"the %s lifecycle rows equal a direct rebuild of the same party" % str(step.roles))
		var statuses_ok: bool = true
		var poisons_ok: bool = true
		for slot in range(step.roles.size()):
			statuses_ok = statuses_ok and state.equipment.party_statuses[slot].size() == 16
			poisons_ok = poisons_ok and state.equipment.party_poisons[slot] is PackedByteArray
			poisons_ok = poisons_ok and state.equipment.party_poisons[slot].size() == 64
		check(statuses_ok, "every %s status row keeps sixteen I2 values" % str(step.roles))
		check(poisons_ok, "every %s slot keeps sixteen 4-byte poison records" % str(step.roles))
		check(state.inventory_bytes.decode_u16(2) == 3, "the seeded quantity survives the %s rebuild" % str(step.roles))

	# The re-expanded 1 -> 2 step is the reviewed failure; prove it again through
	# the sprite ids the host would load for the final three-member party.
	var ids: Array = []
	for role in range(state.equipment.party_roles.size()):
		ids.append(state.equipment.party_fields[role].battle_sprite_word)
	check(ids.size() == 3, "the re-expanded party exposes three sprite projections")

	# A backing without records for the requested members is a named failure and
	# leaves the applied composition untouched.
	var thin: Dictionary = {"globals": {"current_scene": 1, "battle_mode": 0, "member_last": 0, "follower_count": 0},
		"equipment": kernel.initial_state([0]),
		"party_records": [{"role_id": 0, "screen_x": 160, "screen_y": 112, "current_frame": 3}],
		"inventory_bytes": _zero(1536)}
	var refused = commands.consume(thin, {"words": [0x0075, 2, 3, 0], "entry": 1, "event_id": 0})
	check(refused.has("error") and str(refused.error).contains("records"),
		"growth without member records is a named failure: " + str(refused.get("error", "")))
	check(thin.equipment.party_roles == [0] and thin.equipment.party_fields.size() == 1,
		"a refused growth leaves the previous composition intact")

	var passed = results.filter(func(r): return r.passed).size()
	var out = FileAccess.open(args[1], FileAccess.WRITE)
	if out == null: quit(2); return
	out.store_string(JSON.stringify({"passed": passed, "failed": failed, "checks": results}, "\t"))
	out.close()
	print("party lifecycle: ", results.size(), " checks, ", failed, " failed")
	quit(0 if failed == 0 else 1)
