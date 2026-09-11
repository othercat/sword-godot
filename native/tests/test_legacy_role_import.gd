# SPDX-License-Identifier: MIT
extends SceneTree
const Package = preload("res://src/native_package.gd")
const Session = preload("res://src/native_session.gd")
const Save = preload("res://src/native_save.gd")
const Schema = preload("res://src/native_schema.gd")
const Growth = preload("res://src/native_progression.gd")
const RECEIPTS = "pal.studio.legacy_role_imports"
var checks: Array = []
var saves: Array = []
var failed: int = 0
var output: String

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2: quit(2); return
	output = args[1]
	if FileAccess.file_exists(output.path_join("results.json")): push_error("Use a fresh evidence directory"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	check(fixtures.size() == 6, "six source-role compiler fixtures supplied")
	var roles: Array = []
	for fixture in fixtures:
		roles.append(int(fixture.role_index))
		var label: String = "role-" + str(int(fixture.role_index))
		check(Schema.digest(FileAccess.get_file_as_bytes(fixture.path)) == fixture.sha256, "exact Studio fixture bytes: " + label)
		var package = Package.new()
		check(package.load_package(fixture.path), "ordinary package admission: " + label)
		if not package.error.is_empty(): push_error(package.error); _finish(); return
		var hero: String = fixture.instance_id
		var receipt: Dictionary = package.world.extensions[RECEIPTS][hero]
		check(receipt.source_fingerprint == fixture.source_fingerprint and int(receipt.role_index) == int(fixture.role_index), "portable source and role identity: " + label)
		check(receipt.data3.sha256 == fixture.data3_sha256 and receipt.data3.raw_hex.length() == 1800, "complete opaque DATA3 retained: " + label)
		check(receipt.applied_field_indices == [3, 7, 8, 9, 10] and not receipt.remaining_fields_applied, "partial import scope remains explicit: " + label)
		var source_before: Dictionary = receipt.duplicate(true)
		var session = Session.new()
		check(session.activate(package, 1000), "new game activates: " + label)
		if session.state.is_empty(): push_error(session.error); _finish(); return
		var actor: Dictionary = session.entity(hero)
		var definition: Dictionary = package.index.actor_definitions[actor.definition_id]
		var limits: Dictionary = Growth.stats(package, actor)
		check(definition.display_name == fixture.name, "decoded source name preserved: " + label)
		check(actor.hp == fixture.hp and actor.mp == fixture.mp, "source current HP and MP preserved: " + label)
		check(limits.max_hp == fixture.max_hp and limits.max_mp == fixture.max_mp, "source effective maxima preserved: " + label)
		check(session.validate_saved(session.snapshot()).is_empty(), "imported initial checkpoint valid: " + label)
		actor.hp = mini(7, int(limits.max_hp)); actor.mp = mini(3, int(limits.max_mp))
		var storage = Save.new(output.path_join(label + "-saves")); storage.source_origin = "modified"
		check(storage.save(session), "actual persistent save written: " + label)
		if storage.last_path.is_empty(): push_error(storage.error); _finish(); return
		var save_before: PackedByteArray = FileAccess.get_file_as_bytes(storage.last_path)
		var fresh = Session.new()
		check(fresh.activate(package, 2000), "independent new session activates: " + label)
		check(storage.load_into(fresh, storage.last_path, 3000), "actual save restores into new session: " + label)
		check(fresh.entity(hero).hp == actor.hp and fresh.entity(hero).mp == actor.mp, "loaded values are not reset to imported initial values: " + label)
		check(package.world.extensions[RECEIPTS][hero] == source_before, "runtime and restore keep source receipt intact: " + label)
		check(FileAccess.get_file_as_bytes(storage.last_path) == save_before, "save load is read-only: " + label)
		saves.append({"role_index": int(fixture.role_index), "path": storage.last_path, "package_sha256": fixture.sha256, "hp": actor.hp, "mp": actor.mp})
	roles.sort()
	check(roles == [0, 1, 2, 3, 4, 5], "each original disk role covered once")
	_finish()

func _finish() -> void:
	var report: Dictionary = {"checks": checks, "saves": saves, "passed": checks.size() - failed, "failed": failed,
		"real_source_fields": true, "headless": true, "original_rule_parity": false, "original_playthrough": false}
	var file = FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ", true)); file.close()
	print("Legacy role import checks: %d passed, %d failed; %s" % [checks.size() - failed, failed, output])
	quit(0 if failed == 0 else 1)
